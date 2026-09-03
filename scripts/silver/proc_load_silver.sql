-- Data with Baraa's actual procedure: https://github.com/DataWithBaraa/sql-data-warehouse-project/blob/main/scripts/silver/proc_load_silver.sql
-- this file archives my step-by-step notes in the Silver Layer tutorial
-- Start:


-- tips:
-- go table by table, column by column
-- create queries to check for the quality of a row (low cardinality (small options) in gender/civil status, plausible dates (end date after start date), etc.)
-- if connection between tables was found through their data, standardize the data

-- crm_cust_info:
-- nulls and duplicate checker in primary key
SELECT cst_id, COUNT(*)
FROM bronze.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1 OR cst_id IS NULL

-- gets most latest data from duplicates (early sql)
SELECT *
FROM (
	SELECT *,
	ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) as flag_last
	FROM bronze.crm_cust_info
	WHERE cst_id IS NOT NULL
)t WHERE flag_last = 1 AND [dupe primary keys here]

-- unwanted space checker
SELECT cst_firstname [<-any string column]
FROM bronze.crm_cust_info
WHERE cst_firstname != TRIM(cst_firstname)

-- check for options outside of expected (ex: M/F gender)
SELECT DISTINCT cst_gndr
FROM bronze.crm_cust_info

-- final result of cleaned crm_cust_info
SELECT
cst_id,
cst_key,
TRIM(cst_firstname) AS cst_firstname,
TRIM(cst_lastname) AS cst_lastname,
CASE
	WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
	WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
	ELSE 'n/a'
END AS cst_marital_status,
CASE
	WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
	WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
	ELSE 'n/a'
END AS cst_gndr,
cst_create_date
FROM (
	SELECT *,
	ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) as flag_last
	FROM bronze.crm_cust_info
	WHERE cst_id IS NOT NULL
)t WHERE flag_last = 1 AND [dupe primary keys here but flag_last can be last]

-- put above final clean sql when done executing
INSERT INTO silver.crm_cust_info (
	cst_id,
	cst_key,
	cst_firstname,
	cst_lastname,
	cst_marital_status,
	cst_gndr,
	cst_create_date
)
-- replace bronze. to silver. for the checkers above to verify clean data after insert

-- crm_prd_info:
-- final clean sql
SELECT
	prd_id,
	prd_key,
--first part to join cat id
	REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,
--second part to join sales details
	SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,
	prd_nm,
	ISNULL(prd_cost, 0) AS prd_cost,
	--use CASE [function] for simple conditions
	CASE UPPER(TRIM(prd_line))
		WHEN 'M' THEN 'Mountain'
		WHEN 'R' THEN 'Road'
		WHEN 'S' THEN 'Other Sales'
		WHEN 'T' THEN 'Touring'
		ELSE 'n/a'
END AS prd_line,
	CAST(prd_start_dt AS DATE) AS prd_start_dt,
	CAST(LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt)-1 AS DATE) AS prd_end_dt
FROM bronze.crm_prd_info
--cat id not available in second table. Can substitute with sales_details substring
-- WHERE REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') NOT IN (SELECT DISTINCT id FROM bronze.erp_px_cat_g1v2)

-- unwanted space checker
SELECT prd_nm [<-any string column]
FROM bronze.crm_prd_info
WHERE prd_nm != TRIM(prd_nm)

-- negative num checker
SELECT prd_cost
FROM bronze.crm_prd_info
WHERE prd_cost < 0 OR prd_cost IS NULL

-- check for options outside of expected (ex: M/F gender)
SELECT DISTINCT prd_line [use other rows with options too]
FROM bronze.crm_prd_info

-- invalid date checker
SELECT *
FROM bronze.crm_prd_info
WHERE prd_end_dt < prd_start_dt

-- put above final clean sql when done executing
-- modified from DATETIME to DATE and added cat_id to make data clean
IF OBJECT_ID('silver.crm_prd_info', 'U') IS NOT NULL 
	DROP TABLE 'silver.crm_prd_info'; 
CREATE TABLE silver.crm_prd_info ( 
	prd_id INT, 
	cat_id NVARCHAR(50),
	prd_key NVARCHAR(50), 
	prd_nm NVARCHAR(50), 
	prd_cost INT, 
	prd_line NVARCHAR(50), 
	prd_start_dt DATE, 
	prd_end_dt DATE,
	dwh_create_date DATETIME2 DEFAULT GETDATE()
); 

INSERT INTO silver.crm_prd_info (
	prd_id, 
	cat_id,
	prd_key, 
	prd_nm, 
	prd_cost, 
	prd_line, 
	prd_start_dt, 
	prd_end_dt
)


-- crm_sales_details:
-- do unwanted spaces checker for sls_ord_num
-- final sql
SELECT
sls_ord_num,
sls_prd_key,
sls_cust_id,
CASE WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL
	ELSE cast(CAST(sls_order_dt AS VARCHAR) AS DATE)
END AS sls_order_dt,
CASE WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL
	ELSE cast(CAST(sls_ship_dt AS VARCHAR) AS DATE)
END AS sls_ship_dt,
CASE WHEN sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL
	ELSE cast(CAST(sls_due_dt AS VARCHAR) AS DATE)
END AS sls_due_dt,
CASE WHEN sls_sales IS NULL OR sls_sales <=0 OR sls_sales != sls_quantity * ABS(sls_price)
	THEN sls_quantity * ABS(sls_price)
	ELSE sls_sales
END AS sls_sales,
sls_quantity,
CASE WHEN sls_price IS NULL OR sls_price <= 0
	THEN sls_sales / NULLIF(sls_quantity, 0)
	ELSE sls_price
END AS sls_price,
FROM bronze.crm_sales_details
-- check if there are keys missing in prd_info. cust_info also check. Silver can now be used since they're clean
WHERE sls_prd_key NOT IN (SELECT prd_key FROM silver.crm_prd_info)

-- invalid date checker (want to do into to date)
SELECT
NULLIF(sls_order_dt, 0) sls_order_dt
FROM bronze.crm_sales_details
WHERE sls_order_dt <=0
OR LEN(sls_order_dt) != 8
OR sls_order_dt > 20500101
OR sls_order_dt < 19900101
-- invalid date order (start dt later than ship/due)
SELECT *
FROM bronze.crm_sales_details
WHERE sls_order_dt > sls_ship_dt OR sls_order_dt > sls_due_dt

-- data consistency between sales, qty, and price
-- sales = qty * price, val != NULL, 0, or negative
SELECT DISTINCT
sls_sales AS old_sls_sales,
sls_quantity,
sls_price AS old_sls_price,
-- after talking with expert, sample rules given for these cases to make the values good
CASE WHEN sls_sales IS NULL OR sls_sales <=0 OR sls_sales != sls_quantity * ABS(sls_price)
	THEN sls_quantity * ABS(sls_price)
	ELSE sls_sales
END AS sls_sales,

CASE WHEN sls_price IS NULL OR sls_price <= 0
	THEN sls_sales / NULLIF(sls_quantity, 0)
	ELSE sls_price
END AS sls_price,
-- end of bad numbers rules
FROM bronze.crm_sales_details
WHERE sls_sales != sls_quantity * sls_price
OR sls_sales IS NULL OR sls_quantity IS NULL OR sls_price IS NULL
OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0
ORDER BY sls_sales, sls_quantity, sls_price

-- (above this) if bad results on all rows, ask experts on next step

-- silver table redo cuz property change
IF OBJECT_ID('silver.crm_sales_details', 'U') IS NOT NULL 
	DROP TABLE 'silver.crm_sales_details'; 
CREATE TABLE silver.crm_sales_details ( 
	sls_ord_num INT, 
	sls_prd_key NVARCHAR(50), 
	sls_cust_id INT, 
	sls_order_dt DATE, 
	sls_ship_dt DATE, 
	sls_due_dt DATE, 
	sls_sales INT, 
	sls_quantity INT, 
	sls_price INT,
	dwh_create_date DATETIME2 DEFAULT GETDATE()
); 

INSERT INTO silver.crm_sales_details(
	sls_ord_num, 
	sls_prd_key, 
	sls_cust_id, 
	sls_order_dt, 
	sls_ship_dt, 
	sls_due_dt, 
	sls_sales, 
	sls_quantity, 
	sls_price
); 


-- erp_cust_az12:
-- cid check
SELECT
cid,
CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
	ELSE cid
END cid,
bdate, gen
FROM bronze.erp_cust_az12
-- under adds to query which checks if unmatched data with silver
WHERE CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
	ELSE cid
END NOT IN (SELECT DISTINCT cst_key FROM silver.crm_cust_info)

--out of range bdates; report source system for next step or make them null or only null the extremes
SELECT DISTINCT
bdate
FROM bronze.erp_cust_az12
WHERE bdate < '1926-01-01' OR bdate > GETDATE()

-- gender standardization
SELECT DISTINCT gen,
CASE WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
	WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
	ELSE 'n/a'
END AS gen
FROM bronze.erp_cust_az12

-- final sql
SELECT
cid,
CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
	ELSE cid
END cid,
CASE WHEN bdate > GETDATE() THEN NULL
	ELSE bdate
END AS bdate,
CASE WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
	WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
	ELSE 'n/a'
END AS gen
FROM bronze.erp_cust_az12
-- under adds to query which checks if unmatched data with silver
WHERE CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
	ELSE cid
END NOT IN (SELECT DISTINCT cst_key FROM silver.crm_cust_info)

-- above final sql
INSERT INTO silver.erp_cust_az12 (cid, bdate, gen)


-- erp_loc_a101:
-- check connected tables/keys
SELECT cst_key FROM silver.crm_cust_info;

-- country standardization
SELECT DISTINCT cnty
FROM bronze.erp_loc_a101
ORDER BY cntry

-- final sql
SELECT
REPLACE(cid, '-', '') cid,
CASE WHEN TRIM(cntry) = 'DE' THEN 'Germany'
	WHEN TRIM(cntry) = ('US', 'USA') THEN 'United States'
	WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
	ELSE TRIM(cntry)
END
FROM bronze.erp_loc_a101

-- above final sql
INSERT INTO silver.erp_loc_a101 (cid, cntry)

-- check
SELECT * FROM silver.erp_loc_a101


-- erp_px_cat_g1v2:
-- id checker not needed cuz of previous cat_id use

-- unwanted spaces
SELECT * FROM bronze.erp_px_cat_g1v2
WHERE cat != TRIM(cat) OR subcat != TRIM(subcat) OR maintenance != TRIM(maintenance)

-- standardization
SELECT DISTINCT
cat -- or subcat or maint
FROM bronze.erp_px_cat_g1v2

-- final sql (no change needed because the table was clean already. Though still insert from bronze layer)
INSERT INTRO silver.erp_px_cat_g1v2 (id, cat, subcat, maintenance)
SELECT
id,
cat,
subcat,
maintenance
FROM bronze.erp_px_cat_g1v2

-- TRUNCATE TABLE before every insert
