# Banking Transaction Management System (MySQL)

A complete end‑to‑end **SQL portfolio project** built using **MySQL**, designed to showcase skills in ACID transactions, triggers, stored procedures, indexing, database design, and audit logging.

This project is production‑style and ready to upload on **GitHub**.

---

## 📌 **Project Overview**

The **Banking Transaction Management System** simulates real-world banking operations including:

* Account creation
* Deposits & withdrawals
* Secure fund transfers
* Fraud detection
* Transaction audit logging
* ACID-compliant processes

This system demonstrates your SQL expertise with MySQL transactions, triggers, procedures, indexing, and error handling.

---

## 🎯 **Key Features**

### ✅ **ACID Transactions**

Fund transfers are handled using `START TRANSACTION`, `COMMIT`, and `ROLLBACK` ensuring atomicity and consistency.

### ✅ **Fraud Detection Trigger**

Custom trigger detects suspicious activity:

* High-value withdrawals
* Rapid repeated transactions
* Unusual debit patterns

### ✅ **Stored Procedures**

Includes:

* `sp_transfer_funds` (core ACID procedure)
* `sp_get_account_statement` (paginated results)

### ✅ **Indexing for Speed**

Indexes added on:

* `account_id`
* `txn_time`
* `txn_type`

### ✅ **Audit Logging**

Every transfer is logged in `transfer_audit` with execution status.

---

## 🗂️ **Database Schema**

```
accounts
transactions
fraud_alerts
transfer_audit
```

Includes foreign keys, timestamps, constraints, and indexing.

---

## 💾 **Repository Structure**

```
banking-transaction-system/
│
├── README.md                     # Project documentation
├── sql/
│   ├── 01_create_tables.sql      # Schema + constraints
│   ├── 02_insert_sample_data.sql # Demo dataset
│   ├── 03_procedures.sql         # Stored procedures
│   ├── 04_triggers.sql           # Trigger for fraud detection
│   ├── 05_indexes.sql            # Index creation scripts
│   ├── 06_test_cases.sql         # Testing scripts
│
├── docs/
│   ├── architecture_diagram.png  # Optional ER diagram
│   ├── data_flow.png             # Optional data flow diagram
│
└── exports/
    ├── sample_reports/           # Statement outputs
    └── logs/
```

---

## ▶️ **How to Run the Project (MySQL Workbench)**

1. Clone or download the repository.
2. Open MySQL Workbench.
3. Run files in this order:

```
01_create_tables.sql
02_insert_sample_data.sql
05_indexes.sql
03_procedures.sql
04_triggers.sql
06_test_cases.sql
```

4. Test functions using:

```
CALL sp_transfer_funds(1, 2, 500);
CALL sp_get_account_statement(1, 1, 10);
```

---

## 📌 **Sample Resume Line**

**Developed a complete banking transaction system using MySQL with ACID-compliant stored procedures, fraud‑detection triggers, indexing strategies, and audit logs to ensure secure and optimized database operations.**

---

## ⭐ Future Enhancements

* Role‑based access control (RBAC)
* Transaction limits based on customer tier
* Monthly account statements automation
* Integration with Power BI for visualization

---

## 🤝 Contributing

Pull requests are welcome! For major changes, open an issue first.

---

## 📧 Contact

If you'd like help improving this project or adding analytics dashboards, feel free to connect!
