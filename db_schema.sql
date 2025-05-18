-- SDCKL Student Printing Management System Database Schema

-- Drop existing tables if they exist
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS printing_requests;
DROP TABLE IF EXISTS wallet;
DROP TABLE IF EXISTS students;

-- Create table for students
CREATE TABLE students (
    student_id VARCHAR(20) PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,  -- For storing hashed passwords
    department VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Create table for e-wallet
CREATE TABLE wallet (
    wallet_id INT AUTO_INCREMENT PRIMARY KEY,
    student_id VARCHAR(20) NOT NULL,
    balance DECIMAL(10, 2) DEFAULT 0.00,
    last_topup_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (student_id) REFERENCES students(student_id)
);

-- Create table for printing requests
CREATE TABLE printing_requests (
    request_id INT AUTO_INCREMENT PRIMARY KEY,
    student_id VARCHAR(20) NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    file_type VARCHAR(10) NOT NULL,
    num_copies INT NOT NULL DEFAULT 1,
    num_pages INT NOT NULL,
    paper_size ENUM('A4', 'A3', 'Letter') DEFAULT 'A4',
    print_type ENUM('Black & White', 'Color') DEFAULT 'Black & White',
    double_sided BOOLEAN DEFAULT FALSE,
    status ENUM('Pending', 'Processing', 'Completed', 'Cancelled') DEFAULT 'Pending',
    total_cost DECIMAL(10, 2) NOT NULL,
    request_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completion_date TIMESTAMP,
    FOREIGN KEY (student_id) REFERENCES students(student_id)
);

-- Create table for wallet transactions
CREATE TABLE transactions (
    transaction_id INT AUTO_INCREMENT PRIMARY KEY,
    wallet_id INT NOT NULL,
    student_id VARCHAR(20) NOT NULL,
    transaction_type ENUM('Topup', 'Print Payment', 'Refund') NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    reference_no VARCHAR(50) UNIQUE NOT NULL,
    status ENUM('Success', 'Failed', 'Pending') DEFAULT 'Pending',
    transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (wallet_id) REFERENCES wallet(wallet_id),
    FOREIGN KEY (student_id) REFERENCES students(student_id)
);

-- Create table for printing costs configuration
CREATE TABLE printing_costs (
    cost_id INT AUTO_INCREMENT PRIMARY KEY,
    paper_size ENUM('A4', 'A3', 'Letter') NOT NULL,
    print_type ENUM('Black & White', 'Color') NOT NULL,
    cost_per_page DECIMAL(10, 2) NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Insert default printing costs
INSERT INTO printing_costs (paper_size, print_type, cost_per_page) VALUES
('A4', 'Black & White', 0.10),
('A4', 'Color', 0.50),
('A3', 'Black & White', 0.20),
('A3', 'Color', 1.00),
('Letter', 'Black & White', 0.10),
('Letter', 'Color', 0.50);

-- Create views for easy reporting

-- View for student wallet balance
CREATE VIEW vw_student_wallet_balance AS
SELECT 
    s.student_id,
    s.full_name,
    s.department,
    w.balance,
    w.last_topup_date
FROM students s
JOIN wallet w ON s.student_id = w.student_id;

-- View for printing history
CREATE VIEW vw_printing_history AS
SELECT 
    pr.request_id,
    pr.student_id,
    s.full_name,
    pr.file_name,
    pr.num_copies,
    pr.num_pages,
    pr.paper_size,
    pr.print_type,
    pr.double_sided,
    pr.status,
    pr.total_cost,
    pr.request_date,
    pr.completion_date
FROM printing_requests pr
JOIN students s ON pr.student_id = s.student_id;

-- View for transaction history
CREATE VIEW vw_transaction_history AS
SELECT 
    t.transaction_id,
    t.student_id,
    s.full_name,
    t.transaction_type,
    t.amount,
    t.reference_no,
    t.status,
    t.transaction_date
FROM transactions t
JOIN students s ON t.student_id = s.student_id;

-- Create stored procedures

-- Procedure to add new student with wallet
DELIMITER //
CREATE PROCEDURE sp_create_student(
    IN p_student_id VARCHAR(20),
    IN p_full_name VARCHAR(100),
    IN p_email VARCHAR(100),
    IN p_password VARCHAR(255),
    IN p_department VARCHAR(50)
)
BEGIN
    START TRANSACTION;
    
    -- Insert student
    INSERT INTO students (student_id, full_name, email, password, department)
    VALUES (p_student_id, p_full_name, p_email, p_password, p_department);
    
    -- Create wallet for student
    INSERT INTO wallet (student_id) VALUES (p_student_id);
    
    COMMIT;
END //
DELIMITER ;

-- Procedure to process printing request
DELIMITER //
CREATE PROCEDURE sp_process_printing_request(
    IN p_student_id VARCHAR(20),
    IN p_file_name VARCHAR(255),
    IN p_file_type VARCHAR(10),
    IN p_num_copies INT,
    IN p_num_pages INT,
    IN p_paper_size ENUM('A4', 'A3', 'Letter'),
    IN p_print_type ENUM('Black & White', 'Color'),
    IN p_double_sided BOOLEAN
)
BEGIN
    DECLARE v_total_cost DECIMAL(10, 2);
    DECLARE v_wallet_balance DECIMAL(10, 2);
    DECLARE v_wallet_id INT;
    
    -- Calculate total cost
    SELECT cost_per_page * p_num_pages * p_num_copies
    INTO v_total_cost
    FROM printing_costs 
    WHERE paper_size = p_paper_size AND print_type = p_print_type;
    
    -- Get wallet balance and ID
    SELECT wallet_id, balance 
    INTO v_wallet_id, v_wallet_balance
    FROM wallet 
    WHERE student_id = p_student_id;
    
    -- Check if sufficient balance
    IF v_wallet_balance >= v_total_cost THEN
        START TRANSACTION;
        
        -- Create printing request
        INSERT INTO printing_requests (
            student_id, file_name, file_type, num_copies, num_pages,
            paper_size, print_type, double_sided, total_cost
        ) VALUES (
            p_student_id, p_file_name, p_file_type, p_num_copies, p_num_pages,
            p_paper_size, p_print_type, p_double_sided, v_total_cost
        );
        
        -- Deduct from wallet
        UPDATE wallet 
        SET balance = balance - v_total_cost
        WHERE student_id = p_student_id;
        
        -- Record transaction
        INSERT INTO transactions (
            wallet_id, student_id, transaction_type, amount, reference_no, status
        ) VALUES (
            v_wallet_id,
            p_student_id,
            'Print Payment',
            v_total_cost,
            CONCAT('PRN', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s')),
            'Success'
        );
        
        COMMIT;
    ELSE
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Insufficient wallet balance';
    END IF;
END //
DELIMITER ;

-- Procedure to top up wallet
DELIMITER //
CREATE PROCEDURE sp_topup_wallet(
    IN p_student_id VARCHAR(20),
    IN p_amount DECIMAL(10, 2)
)
BEGIN
    DECLARE v_wallet_id INT;
    
    -- Get wallet ID
    SELECT wallet_id INTO v_wallet_id
    FROM wallet WHERE student_id = p_student_id;
    
    START TRANSACTION;
    
    -- Update wallet balance
    UPDATE wallet 
    SET 
        balance = balance + p_amount,
        last_topup_date = CURRENT_TIMESTAMP
    WHERE student_id = p_student_id;
    
    -- Record transaction
    INSERT INTO transactions (
        wallet_id, student_id, transaction_type, amount, reference_no, status
    ) VALUES (
        v_wallet_id,
        p_student_id,
        'Topup',
        p_amount,
        CONCAT('TOP', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s')),
        'Success'
    );
    
    COMMIT;
END //
DELIMITER ;

-- Create triggers

-- Trigger to update wallet balance after refund
DELIMITER //
CREATE TRIGGER trg_after_refund
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    IF NEW.transaction_type = 'Refund' AND NEW.status = 'Success' THEN
        UPDATE wallet
        SET balance = balance + NEW.amount
        WHERE wallet_id = NEW.wallet_id;
    END IF;
END //
DELIMITER ;

-- Sample data insertion
INSERT INTO students (student_id, full_name, email, password, department) VALUES
('2023001', 'John Doe', 'john.doe@sdckl.edu', SHA2('password123', 256), 'Computer Science'),
('2023002', 'Jane Smith', 'jane.smith@sdckl.edu', SHA2('password456', 256), 'Engineering');

-- Insert initial wallet records for sample students
INSERT INTO wallet (student_id, balance) VALUES
('2023001', 50.00),
('2023002', 30.00);
