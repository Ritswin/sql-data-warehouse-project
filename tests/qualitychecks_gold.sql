--Data with Baraa's quality checks for gold layer: https://github.com/DataWithBaraa/sql-data-warehouse-project/blob/main/tests/quality_checks_gold.sql
--gender consistency code
SELECT DISTINCT
	ci.cst_gndr,
	ca.gen,
	CASE WHEN ci.cst_gndr != 'n/a' THEN ci.cst_gndr 
		ELSE COALESCE(ca.gen, 'n/a')
	END AS new_gen
FROM silver.crm_cust_info ci
LEFT JOIN silver.erp_cust_az12 ca
ON ci.cst_key = ca.cid
LEFT JOIN silver.erp_loc_a101 la
ON ci.cst_key = la.cid

--checks if gold table creation is good by comapring with relationships
select * from gold.fact_sales f
left join gold.dim_customers c
on c.customer_key = f.customer_key
where c.customer_key is null
