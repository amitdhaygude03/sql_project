-- Banking Transaction Management System (SQL Server - T-SQL)
-- Project: ACID-compliant fund transfer, triggers for fraud detection, optimized indexing
-- README (at top):
-- 1) This script is written for Microsoft SQL Server (T-SQL). It creates schema, sample data,
--    indexes, stored procedure for fund transfer (with transaction & error handling),
--    a fraud-detection trigger, sample queries, and tests.
-- 2) Run in order in a new database (or change USE [YourDB] at top).
-- 3) To adapt to MySQL/PostgreSQL, some syntax (TRY/CATCH, THROW, sequences) needs changes.

-- =============================================
-- 0. Create test database (optional)
-- =============================================
IF DB_ID('BankingDemo') IS NOT NULL
BEGIN
    ALTER DATABASE BankingDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE BankingDemo;
END
CREATE DATABASE BankingDemo;
GO
USE BankingDemo;
GO

-- =============================================
-- 1. Schema: Accounts, Transactions, FraudAlerts, Audit
-- =============================================

-- Accounts table: holds current balance (decimal) and metadata
CREATE TABLE dbo.Accounts (
    AccountID INT IDENTITY(1000,1) PRIMARY KEY,
    AccountNumber VARCHAR(20) NOT NULL UNIQUE,
    AccountHolderName NVARCHAR(200) NOT NULL,
    AccountType VARCHAR(20) NOT NULL DEFAULT('SAVINGS'),
    Balance DECIMAL(18,2) NOT NULL DEFAULT(0.00),
    IsActive BIT NOT NULL DEFAULT(1),
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    LastUpdatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);

-- Transactions table: ledger of all transactions (debits/credits)
CREATE TABLE dbo.Transactions (
    TransactionID BIGINT IDENTITY(1,1) PRIMARY KEY,
    AccountID INT NOT NULL REFERENCES dbo.Accounts(AccountID),
    TransactionType CHAR(1) NOT NULL, -- 'C' = Credit, 'D' = Debit
    Amount DECIMAL(18,2) NOT NULL CHECK (Amount > 0),
    RelatedAccountID INT NULL, -- for transfers
    TransactionTime DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    Description NVARCHAR(500) NULL,
    ProcessedBy NVARCHAR(100) NULL
);

-- FraudAlerts table: stores alerts raised by trigger
CREATE TABLE dbo.FraudAlerts (
    AlertID BIGINT IDENTITY(1,1) PRIMARY KEY,
    AccountID INT NOT NULL,
    TransactionID BIGINT NULL,
    AlertType NVARCHAR(100) NOT NULL,
    AlertMessage NVARCHAR(1000) NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    IsResolved BIT NOT NULL DEFAULT(0)
);

-- Audit table: log of transfers (optional more detail)
CREATE TABLE dbo.TransferAudit (
    AuditID BIGINT IDENTITY(1,1) PRIMARY KEY,
    FromAccountID INT NOT NULL,
    ToAccountID INT NOT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    TransferTime DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    Status NVARCHAR(20) NOT NULL,
    Message NVARCHAR(1000) NULL
);

-- =============================================
-- 2. Indexes and performance considerations
-- =============================================
-- Cover common queries: lookup by AccountNumber, recent transactions by AccountID and TransactionTime
CREATE UNIQUE INDEX IX_Accounts_AccountNumber ON dbo.Accounts(AccountNumber);
CREATE NONCLUSTERED INDEX IX_Transactions_AccountID_TransactionTime ON dbo.Transactions(AccountID, TransactionTime DESC);
CREATE NONCLUSTERED INDEX IX_Transactions_TransactionTime ON dbo.Transactions(TransactionTime DESC);

-- =============================================
-- 3. Sample data insertion
-- =============================================
INSERT INTO dbo.Accounts (AccountNumber, AccountHolderName, AccountType, Balance)
VALUES
('ACC10001','Amit Kumar','SAVINGS', 50000.00),
('ACC10002','Neha Sharma','SAVINGS', 150000.00),
('ACC10003','Ravi Patel','CURRENT', 2000.00),
('ACC10004','Sneha Iyer','SAVINGS', 1000000.00);

-- Add a few sample transactions
INSERT INTO dbo.Transactions (AccountID, TransactionType, Amount, Description, ProcessedBy)
VALUES
(1000,'C',50000,'Initial deposit','system'),
(1001,'C',150000,'Initial deposit','system'),
(1002,'C',2000,'Initial deposit','system'),
(1003,'C',1000000,'Initial deposit','system');

-- =============================================
-- 4. Stored procedure: Transfer funds (ACID-compliant)
-- =============================================
-- Usage: EXEC dbo.sp_TransferFunds @FromAccountNumber='ACC10001', @ToAccountNumber='ACC10002', @Amount=1000.00, @ProcessedBy='api_user'
-- It performs debit from source and credit to destination inside a single transaction.

IF OBJECT_ID('dbo.sp_TransferFunds','P') IS NOT NULL
    DROP PROCEDURE dbo.sp_TransferFunds;
GO

CREATE PROCEDURE dbo.sp_TransferFunds
    @FromAccountNumber VARCHAR(20),
    @ToAccountNumber VARCHAR(20),
    @Amount DECIMAL(18,2),
    @ProcessedBy NVARCHAR(100) = 'system'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FromAccountID INT, @ToAccountID INT;

    BEGIN TRY
        -- Start explicit transaction
        BEGIN TRANSACTION;

        -- Obtain account ids with UPDLOCK, HOLDLOCK to prevent concurrent race conditions
        SELECT @FromAccountID = AccountID FROM dbo.Accounts WITH (UPDLOCK, HOLDLOCK) WHERE AccountNumber = @FromAccountNumber AND IsActive = 1;
        SELECT @ToAccountID   = AccountID FROM dbo.Accounts WITH (UPDLOCK, HOLDLOCK) WHERE AccountNumber = @ToAccountNumber   AND IsActive = 1;

        IF @FromAccountID IS NULL
        BEGIN
            THROW 51000, 'Source account not found or inactive.', 1;
        END
        IF @ToAccountID IS NULL
        BEGIN
            THROW 51001, 'Destination account not found or inactive.', 1;
        END
        IF @FromAccountID = @ToAccountID
        BEGIN
            THROW 51002, 'Source and destination accounts cannot be the same.', 1;
        END
        IF @Amount <= 0
        BEGIN
            THROW 51003, 'Transfer amount must be greater than zero.', 1;
        END

        -- Check sufficient balance
        DECLARE @FromBalance DECIMAL(18,2);
        SELECT @FromBalance = Balance FROM dbo.Accounts WITH (UPDLOCK, HOLDLOCK) WHERE AccountID = @FromAccountID;

        IF @FromBalance < @Amount
        BEGIN
            THROW 51004, 'Insufficient funds in source account.', 1;
        END

        -- Debit from source account
        UPDATE dbo.Accounts
        SET Balance = Balance - @Amount,
            LastUpdatedAt = SYSUTCDATETIME()
        WHERE AccountID = @FromAccountID;

        -- Insert debit transaction
        INSERT INTO dbo.Transactions (AccountID, TransactionType, Amount, RelatedAccountID, Description, ProcessedBy)
        VALUES (@FromAccountID, 'D', @Amount, @ToAccountID, CONCAT('Transfer to ', @ToAccountNumber), @ProcessedBy);

        -- Credit to destination account
        UPDATE dbo.Accounts
        SET Balance = Balance + @Amount,
            LastUpdatedAt = SYSUTCDATETIME()
        WHERE AccountID = @ToAccountID;

        -- Insert credit transaction
        INSERT INTO dbo.Transactions (AccountID, TransactionType, Amount, RelatedAccountID, Description, ProcessedBy)
        VALUES (@ToAccountID, 'C', @Amount, @FromAccountID, CONCAT('Transfer from ', @FromAccountNumber), @ProcessedBy);

        -- Write to audit
        INSERT INTO dbo.TransferAudit (FromAccountID, ToAccountID, Amount, Status, Message)
        VALUES (@FromAccountID, @ToAccountID, @Amount, 'SUCCESS', NULL);

        COMMIT TRANSACTION;

        SELECT 1 AS Success, 'Transfer completed successfully.' AS Message;
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrNo INT = ERROR_NUMBER();

        IF XACT_STATE() <> 0
        BEGIN
            ROLLBACK TRANSACTION;
        END

        -- Log audit failure
        INSERT INTO dbo.TransferAudit (FromAccountID, ToAccountID, Amount, Status, Message)
        VALUES (ISNULL(@FromAccountID,-1), ISNULL(@ToAccountID,-1), @Amount, 'FAILED', @ErrMsg);

        -- Re-throw error
        THROW;
    END CATCH
END;
GO

-- =============================================
-- 5. Trigger: Fraud detection on insert into Transactions
--    Simple rules:
--    - Any single transaction above a threshold (e.g., 250000) -> alert
--    - More than 3 debits above a smaller threshold within 1 hour -> alert
-- =============================================

IF OBJECT_ID('dbo.trg_DetectFraud','TR') IS NOT NULL
    DROP TRIGGER dbo.trg_DetectFraud;
GO

CREATE TRIGGER dbo.trg_DetectFraud
ON dbo.Transactions
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @HighSingleTxnThreshold DECIMAL(18,2) = 250000.00;
    DECLARE @MediumTxnThreshold DECIMAL(18,2) = 50000.00;
    DECLARE @WindowMinutes INT = 60;

    -- Check high single transaction(s)
    INSERT INTO dbo.FraudAlerts (AccountID, TransactionID, AlertType, AlertMessage)
    SELECT i.AccountID, i.TransactionID, 'HIGH_VALUE_TXN',
           CONCAT('Single high-value txn of amount ', FORMAT(i.Amount, 'N2'))
    FROM inserted i
    WHERE i.Amount >= @HighSingleTxnThreshold;

    -- Check multiple medium debits within short time frame
    ;WITH RecentHighDebits AS (
        SELECT i.AccountID, i.TransactionID, i.Amount, i.TransactionTime
        FROM inserted i
        WHERE i.TransactionType = 'D' AND i.Amount >= @MediumTxnThreshold
    )
    INSERT INTO dbo.FraudAlerts (AccountID, TransactionID, AlertType, AlertMessage)
    SELECT r.AccountID, NULL, 'MULTI_MEDIUM_DEBITS',
           CONCAT('Multiple debits >= ', FORMAT(@MediumTxnThreshold,'N2'), ' within ', @WindowMinutes, ' minutes')
    FROM RecentHighDebits r
    WHERE (
        SELECT COUNT(1)
        FROM dbo.Transactions t
        WHERE t.AccountID = r.AccountID
          AND t.TransactionType = 'D'
          AND t.TransactionTime >= DATEADD(MINUTE, -@WindowMinutes, r.TransactionTime)
          AND t.TransactionTime <= r.TransactionTime
    ) >= 3
    GROUP BY r.AccountID;
END;
GO

-- =============================================
-- 6. Utility: Stored procedure to get account statement (paginated)
-- =============================================
IF OBJECT_ID('dbo.sp_GetAccountStatement','P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetAccountStatement;
GO

CREATE PROCEDURE dbo.sp_GetAccountStatement
    @AccountNumber VARCHAR(20),
    @FromDate DATETIME2 = NULL,
    @ToDate DATETIME2 = NULL,
    @Page INT = 1,
    @PageSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AccountID INT;
    SELECT @AccountID = AccountID FROM dbo.Accounts WHERE AccountNumber = @AccountNumber;
    IF @AccountID IS NULL
    BEGIN
        THROW 52000, 'Account not found.', 1;
    END

    ;WITH Filtered AS (
        SELECT t.TransactionID, t.AccountID, t.TransactionType, t.Amount, t.RelatedAccountID, t.TransactionTime, t.Description,
               ROW_NUMBER() OVER (ORDER BY t.TransactionTime DESC, t.TransactionID DESC) AS rn
        FROM dbo.Transactions t
        WHERE t.AccountID = @AccountID
          AND (@FromDate IS NULL OR t.TransactionTime >= @FromDate)
          AND (@ToDate IS NULL OR t.TransactionTime <= @ToDate)
    )
    SELECT TransactionID, AccountID, TransactionType, Amount, RelatedAccountID, TransactionTime, Description
    FROM Filtered
    WHERE rn BETWEEN ((@Page-1)*@PageSize + 1) AND (@Page*@PageSize)
    ORDER BY TransactionTime DESC;
END;
GO

-- =============================================
-- 7. Tests: Demonstrate successful and failing transfers
-- =============================================
-- Check balances before
SELECT AccountNumber, AccountID, Balance FROM dbo.Accounts ORDER BY AccountID;

-- Successful transfer: ACC10001 -> ACC10002 amount 1000
EXEC dbo.sp_TransferFunds @FromAccountNumber='ACC10001', @ToAccountNumber='ACC10002', @Amount=1000.00, @ProcessedBy='tester';

-- Transfer causing insufficient funds (should fail)
BEGIN TRY
    EXEC dbo.sp_TransferFunds @FromAccountNumber='ACC10003', @ToAccountNumber='ACC10002', @Amount=500000.00, @ProcessedBy='tester';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- Transfer to non-existent account (should fail)
BEGIN TRY
    EXEC dbo.sp_TransferFunds @FromAccountNumber='ACC10001', @ToAccountNumber='ACC99999', @Amount=10.00, @ProcessedBy='tester';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg;
END CATCH;

-- Check balances after
SELECT AccountNumber, AccountID, Balance FROM dbo.Accounts ORDER BY AccountID;

-- Show transactions for ACC10001
EXEC dbo.sp_GetAccountStatement @AccountNumber='ACC10001', @Page=1, @PageSize=20;

-- Show fraud alerts (none expected for small transfers)
SELECT * FROM dbo.FraudAlerts ORDER BY CreatedAt DESC;

-- =============================================
-- 8. Notes & Extension Ideas
-- =============================================
-- - Improve fraud detection with machine learning scores inserted into Frauds table by an ML job.
-- - Use temporal tables or append-only ledger for compliance (immutability).
-- - Add concurrency tests and large-scale load testing to verify locking strategy.
-- - Add encryption (TDE/Always Encrypted) and role-based security for production.

-- End of script
