-- =====================================================================
-- CineSphere schema (SQLite) - normalised to 3NF
-- Contains: tables + constraints, indexes, triggers (business rules), views
-- =====================================================================
PRAGMA foreign_keys = ON;

-- ---------- Reference / master tables ----------
CREATE TABLE IF NOT EXISTS customer (
    customer_id INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name   TEXT NOT NULL CHECK (length(trim(full_name)) >= 2),
    email       TEXT NOT NULL UNIQUE COLLATE NOCASE,
    phone       TEXT NOT NULL,
    created_at  TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS movie (
    movie_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    title            TEXT NOT NULL CHECK (length(trim(title)) > 0),
    genre            TEXT NOT NULL,
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0),
    language         TEXT NOT NULL,
    rating           TEXT NOT NULL CHECK (rating IN ('G','PG','PG-13','R','NC-17')),
    release_date     TEXT NOT NULL,
    status           TEXT NOT NULL DEFAULT 'Now Showing'
                     CHECK (status IN ('Now Showing','Coming Soon','Archived'))
);

CREATE TABLE IF NOT EXISTS screen (
    screen_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    screen_name TEXT NOT NULL UNIQUE,
    capacity    INTEGER NOT NULL CHECK (capacity > 0),
    screen_type TEXT NOT NULL CHECK (screen_type IN ('Standard','IMAX','Premium','VIP')),
    status      TEXT NOT NULL DEFAULT 'Active' CHECK (status IN ('Active','Maintenance','Closed'))
);

CREATE TABLE IF NOT EXISTS seat (
    seat_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    screen_id   INTEGER NOT NULL REFERENCES screen(screen_id) ON DELETE CASCADE,
    row_label   TEXT NOT NULL,
    seat_number INTEGER NOT NULL CHECK (seat_number > 0),
    seat_type   TEXT NOT NULL CHECK (seat_type IN ('Standard','Premium','VIP')),
    UNIQUE (screen_id, row_label, seat_number)
);

-- ---------- Scheduling ----------
CREATE TABLE IF NOT EXISTS show (
    show_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    movie_id     INTEGER NOT NULL REFERENCES movie(movie_id),
    screen_id    INTEGER NOT NULL REFERENCES screen(screen_id),
    show_date    TEXT NOT NULL,             -- YYYY-MM-DD
    start_time   TEXT NOT NULL,             -- HH:MM
    end_time     TEXT NOT NULL,             -- HH:MM (same day)
    ticket_price REAL NOT NULL CHECK (ticket_price > 0),
    status       TEXT NOT NULL DEFAULT 'Upcoming'
                 CHECK (status IN ('Upcoming','Now Showing','Completed','Cancelled')),
    CHECK (end_time > start_time)
);

-- ---------- Booking / payment ----------
CREATE TABLE IF NOT EXISTS booking (
    booking_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id      INTEGER NOT NULL REFERENCES customer(customer_id),
    show_id          INTEGER NOT NULL REFERENCES show(show_id),
    booking_datetime TEXT NOT NULL,
    booking_status   TEXT NOT NULL CHECK (booking_status IN ('Pending','Confirmed','Cancelled')),
    total_amount     REAL NOT NULL CHECK (total_amount >= 0)
);

-- seat_status lets a cancelled booking release its seats while keeping history.
-- Rule A (one seat per screening) is enforced by the partial UNIQUE index below:
-- UNIQUE(show_id, seat_id) among ACTIVE seat allocations.
CREATE TABLE IF NOT EXISTS booking_seat (
    booking_seat_id INTEGER PRIMARY KEY AUTOINCREMENT,
    booking_id      INTEGER NOT NULL REFERENCES booking(booking_id),
    show_id         INTEGER NOT NULL REFERENCES show(show_id),
    seat_id         INTEGER NOT NULL REFERENCES seat(seat_id),
    price           REAL NOT NULL CHECK (price > 0),
    seat_status     TEXT NOT NULL DEFAULT 'Active' CHECK (seat_status IN ('Active','Released'))
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_booking_seat_active
    ON booking_seat (show_id, seat_id) WHERE seat_status = 'Active';

CREATE TABLE IF NOT EXISTS payment (
    payment_id            INTEGER PRIMARY KEY AUTOINCREMENT,
    booking_id            INTEGER NOT NULL REFERENCES booking(booking_id),
    payment_method        TEXT NOT NULL CHECK (payment_method IN ('Cash','Card','Digital Wallet')),
    amount                REAL NOT NULL CHECK (amount >= 0),
    payment_datetime      TEXT NOT NULL,
    payment_status        TEXT NOT NULL CHECK (payment_status IN ('Paid','Pending','Refunded','Failed')),
    transaction_reference TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS ticket (
    ticket_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    booking_id      INTEGER NOT NULL REFERENCES booking(booking_id),
    booking_seat_id INTEGER NOT NULL UNIQUE REFERENCES booking_seat(booking_seat_id),
    ticket_code     TEXT NOT NULL UNIQUE,
    issued_at       TEXT NOT NULL
);

-- ---------- Concessions ----------
CREATE TABLE IF NOT EXISTS concession_item (
    item_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    item_name      TEXT NOT NULL UNIQUE,
    category       TEXT NOT NULL,
    unit_price     REAL NOT NULL CHECK (unit_price > 0),
    stock_quantity INTEGER NOT NULL CHECK (stock_quantity >= 0),
    status         TEXT NOT NULL DEFAULT 'Active' CHECK (status IN ('Active','Inactive'))
);

CREATE TABLE IF NOT EXISTS concession_sale (
    concession_sale_id INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id        INTEGER REFERENCES customer(customer_id),   -- nullable: walk-in sale
    booking_id         INTEGER REFERENCES booking(booking_id),     -- nullable
    sale_datetime      TEXT NOT NULL,
    total_amount       REAL NOT NULL CHECK (total_amount >= 0)
);

CREATE TABLE IF NOT EXISTS concession_sale_item (
    sale_item_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    concession_sale_id INTEGER NOT NULL REFERENCES concession_sale(concession_sale_id),
    item_id            INTEGER NOT NULL REFERENCES concession_item(item_id),
    quantity           INTEGER NOT NULL CHECK (quantity > 0),
    unit_price         REAL NOT NULL CHECK (unit_price > 0)
);

-- ---------- Cancellation / refund ----------
CREATE TABLE IF NOT EXISTS cancellation (
    cancellation_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    booking_id            INTEGER NOT NULL UNIQUE REFERENCES booking(booking_id),
    cancellation_datetime TEXT NOT NULL,
    reason                TEXT NOT NULL CHECK (length(trim(reason)) > 0),
    refund_percentage     INTEGER NOT NULL CHECK (refund_percentage BETWEEN 0 AND 100),
    refund_amount         REAL NOT NULL CHECK (refund_amount >= 0),
    cancellation_status   TEXT NOT NULL DEFAULT 'Processed' CHECK (cancellation_status IN ('Processed','Rejected'))
);

CREATE TABLE IF NOT EXISTS refund (
    refund_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    cancellation_id INTEGER NOT NULL REFERENCES cancellation(cancellation_id),
    payment_id      INTEGER NOT NULL REFERENCES payment(payment_id),
    refund_amount   REAL NOT NULL CHECK (refund_amount >= 0),
    refund_datetime TEXT NOT NULL,
    refund_status   TEXT NOT NULL DEFAULT 'Processed' CHECK (refund_status IN ('Processed','Pending'))
);

-- ---------- Application users (login) ----------
CREATE TABLE IF NOT EXISTS app_user (
    user_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    username      TEXT NOT NULL UNIQUE,
    full_name     TEXT NOT NULL,
    role          TEXT NOT NULL CHECK (role IN ('Admin','Staff')),
    salt          TEXT NOT NULL,
    password_hash TEXT NOT NULL
);

-- ---------- Indexes ----------
CREATE INDEX IF NOT EXISTS ix_show_screen_date ON show (screen_id, show_date);
CREATE INDEX IF NOT EXISTS ix_booking_show     ON booking (show_id);
CREATE INDEX IF NOT EXISTS ix_booking_customer ON booking (customer_id);
CREATE INDEX IF NOT EXISTS ix_bseat_booking    ON booking_seat (booking_id);
CREATE INDEX IF NOT EXISTS ix_payment_booking  ON payment (booking_id);

-- =====================================================================
-- TRIGGERS (business rules enforced inside the database)
-- =====================================================================

-- Rule B: a screen cannot host two overlapping shows on the same date.
-- Overlap test:  new_start < existing_end AND new_end > existing_start
CREATE TRIGGER IF NOT EXISTS trg_show_no_overlap_insert
BEFORE INSERT ON show
WHEN NEW.status <> 'Cancelled'
BEGIN
    SELECT RAISE(ABORT, 'Schedule conflict: this screen already has a movie during this time.')
    WHERE EXISTS (
        SELECT 1 FROM show s
        WHERE s.screen_id = NEW.screen_id
          AND s.show_date = NEW.show_date
          AND s.status <> 'Cancelled'
          AND NEW.start_time < s.end_time
          AND NEW.end_time   > s.start_time
    );
END;

CREATE TRIGGER IF NOT EXISTS trg_show_no_overlap_update
BEFORE UPDATE OF screen_id, show_date, start_time, end_time ON show
WHEN NEW.status <> 'Cancelled'
BEGIN
    SELECT RAISE(ABORT, 'Schedule conflict: this screen already has a movie during this time.')
    WHERE EXISTS (
        SELECT 1 FROM show s
        WHERE s.screen_id = NEW.screen_id
          AND s.show_date = NEW.show_date
          AND s.show_id <> NEW.show_id
          AND s.status <> 'Cancelled'
          AND NEW.start_time < s.end_time
          AND NEW.end_time   > s.start_time
    );
END;

-- A booked seat must belong to the screen of the show being booked.
CREATE TRIGGER IF NOT EXISTS trg_booking_seat_valid
BEFORE INSERT ON booking_seat
BEGIN
    SELECT RAISE(ABORT, 'Seat does not belong to the screen of this show.')
    WHERE (SELECT screen_id FROM seat WHERE seat_id = NEW.seat_id)
       <> (SELECT screen_id FROM show WHERE show_id = NEW.show_id);
    SELECT RAISE(ABORT, 'Seat allocation show does not match the booking show.')
    WHERE (SELECT show_id FROM booking WHERE booking_id = NEW.booking_id) <> NEW.show_id;
END;

-- Rule E: refund can never exceed the original payment.
CREATE TRIGGER IF NOT EXISTS trg_refund_not_above_payment
BEFORE INSERT ON refund
WHEN NEW.refund_amount > (SELECT amount FROM payment WHERE payment_id = NEW.payment_id)
BEGIN
    SELECT RAISE(ABORT, 'Refund cannot exceed the original payment amount.');
END;

-- Rule E: cancellation is prohibited once the show has started.
CREATE TRIGGER IF NOT EXISTS trg_cancel_before_show_start
BEFORE INSERT ON cancellation
WHEN (SELECT sh.show_date || ' ' || sh.start_time || ':00'
      FROM booking b INNER JOIN show sh ON sh.show_id = b.show_id
      WHERE b.booking_id = NEW.booking_id) <= NEW.cancellation_datetime
BEGIN
    SELECT RAISE(ABORT, 'Cancellation is not allowed after the show has started.');
END;

-- =====================================================================
-- VIEWS (JOIN, LEFT JOIN, GROUP BY, aggregates, CASE, COALESCE, subqueries)
-- =====================================================================

-- Ticket revenue base: payments that were actually collected (Paid, or later Refunded)
CREATE VIEW IF NOT EXISTS vw_ticket_sales AS
SELECT p.payment_id, p.booking_id, p.amount, p.payment_datetime, p.payment_method,
       b.show_id, sh.movie_id, sh.screen_id, sh.show_date
FROM payment p
INNER JOIN booking b  ON b.booking_id = p.booking_id
INNER JOIN show sh    ON sh.show_id   = b.show_id
WHERE p.payment_status IN ('Paid','Refunded');

-- Seats sold / capacity / occupancy per show (LEFT JOIN + derived-table subquery)
CREATE VIEW IF NOT EXISTS vw_show_occupancy AS
SELECT sh.show_id, sh.movie_id, sh.screen_id, m.title AS movie_title, sc.screen_name,
       sh.show_date, sh.start_time, sh.end_time, sh.ticket_price, sh.status,
       sc.capacity,
       COALESCE(sold.seats_sold, 0)                                   AS seats_sold,
       sc.capacity - COALESCE(sold.seats_sold, 0)                     AS available_seats,
       ROUND(100.0 * COALESCE(sold.seats_sold, 0) / sc.capacity, 1)   AS occupancy_pct
FROM show sh
INNER JOIN movie  m  ON m.movie_id   = sh.movie_id
INNER JOIN screen sc ON sc.screen_id = sh.screen_id
LEFT JOIN (SELECT show_id, COUNT(*) AS seats_sold
           FROM booking_seat WHERE seat_status = 'Active'
           GROUP BY show_id) sold ON sold.show_id = sh.show_id;

CREATE VIEW IF NOT EXISTS vw_movie_performance AS
SELECT m.movie_id, m.title, m.genre,
       COUNT(o.show_id)                              AS total_shows,
       COALESCE(SUM(o.seats_sold), 0)                AS tickets_sold,
       ROUND(COALESCE(AVG(o.occupancy_pct), 0), 1)   AS avg_occupancy_pct,
       COALESCE((SELECT SUM(ts.amount) FROM vw_ticket_sales ts
                 WHERE ts.movie_id = m.movie_id), 0) AS ticket_revenue
FROM movie m
LEFT JOIN vw_show_occupancy o ON o.movie_id = m.movie_id AND o.status <> 'Cancelled'
GROUP BY m.movie_id, m.title, m.genre;

CREATE VIEW IF NOT EXISTS vw_screen_utilization AS
SELECT sc.screen_id, sc.screen_name, sc.capacity,
       COUNT(o.show_id) AS total_shows,
       ROUND(COALESCE(SUM((julianday(o.show_date || ' ' || o.end_time)
                         - julianday(o.show_date || ' ' || o.start_time)) * 24), 0), 1) AS scheduled_hours,
       ROUND(COALESCE(AVG(o.occupancy_pct), 0), 1) AS avg_occupancy_pct,
       COALESCE((SELECT SUM(ts.amount) FROM vw_ticket_sales ts
                 WHERE ts.screen_id = sc.screen_id), 0) AS ticket_revenue
FROM screen sc
LEFT JOIN vw_show_occupancy o ON o.screen_id = sc.screen_id AND o.status <> 'Cancelled'
GROUP BY sc.screen_id, sc.screen_name, sc.capacity;

CREATE VIEW IF NOT EXISTS vw_concession_performance AS
SELECT ci.item_id, ci.item_name, ci.category, ci.unit_price, ci.stock_quantity,
       COALESCE(SUM(csi.quantity), 0)                    AS quantity_sold,
       COALESCE(SUM(csi.quantity * csi.unit_price), 0)   AS sales_revenue
FROM concession_item ci
LEFT JOIN concession_sale_item csi ON csi.item_id = ci.item_id
GROUP BY ci.item_id, ci.item_name, ci.category, ci.unit_price, ci.stock_quantity;

CREATE VIEW IF NOT EXISTS vw_cancellation_summary AS
SELECT m.movie_id, m.title,
       COUNT(DISTINCT b.booking_id) AS total_bookings,
       COUNT(DISTINCT c.booking_id) AS cancellations,
       COALESCE(ROUND(100.0 * COUNT(DISTINCT c.booking_id)
                      / NULLIF(COUNT(DISTINCT b.booking_id), 0), 1), 0) AS cancellation_rate_pct,
       COALESCE(SUM(r.refund_amount), 0) AS refund_amount
FROM movie m
LEFT JOIN show sh          ON sh.movie_id = m.movie_id
LEFT JOIN booking b        ON b.show_id = sh.show_id
LEFT JOIN cancellation c   ON c.booking_id = b.booking_id
LEFT JOIN refund r         ON r.cancellation_id = c.cancellation_id
GROUP BY m.movie_id, m.title;

-- Net Revenue = Ticket Revenue + Concession Revenue - Refund Amount
CREATE VIEW IF NOT EXISTS vw_revenue_summary AS
SELECT t.ticket_revenue, c.concession_revenue, r.refund_amount,
       t.ticket_revenue + c.concession_revenue - r.refund_amount AS net_revenue
FROM (SELECT COALESCE(SUM(amount), 0) AS ticket_revenue FROM vw_ticket_sales) t,
     (SELECT COALESCE(SUM(total_amount), 0) AS concession_revenue FROM concession_sale) c,
     (SELECT COALESCE(SUM(refund_amount), 0) AS refund_amount FROM refund) r;

CREATE VIEW IF NOT EXISTS vw_daily_revenue AS
SELECT d AS revenue_date,
       SUM(ticket) AS ticket_revenue, SUM(conc) AS concession_revenue, SUM(ref) AS refund_amount,
       SUM(ticket) + SUM(conc) - SUM(ref) AS net_revenue
FROM (
    SELECT date(payment_datetime) AS d, amount AS ticket, 0 AS conc, 0 AS ref
      FROM payment WHERE payment_status IN ('Paid','Refunded')
    UNION ALL
    SELECT date(sale_datetime), 0, total_amount, 0 FROM concession_sale
    UNION ALL
    SELECT date(refund_datetime), 0, 0, refund_amount FROM refund
)
GROUP BY d;

CREATE VIEW IF NOT EXISTS vw_booking_details AS
SELECT b.booking_id, b.customer_id, c.full_name AS customer_name, c.email,
       m.title AS movie_title, sc.screen_name, sh.show_id, sh.show_date, sh.start_time,
       b.booking_datetime, b.booking_status, b.total_amount,
       (SELECT group_concat(s.row_label || s.seat_number, ', ')
          FROM booking_seat bs INNER JOIN seat s ON s.seat_id = bs.seat_id
         WHERE bs.booking_id = b.booking_id)                                   AS seats,
       (SELECT COUNT(*) FROM booking_seat bs WHERE bs.booking_id = b.booking_id) AS ticket_count,
       COALESCE((SELECT p.payment_status FROM payment p WHERE p.booking_id = b.booking_id
                 ORDER BY p.payment_id DESC LIMIT 1), 'None')                  AS payment_status
FROM booking b
INNER JOIN customer c ON c.customer_id = b.customer_id
INNER JOIN show sh    ON sh.show_id    = b.show_id
INNER JOIN movie m    ON m.movie_id    = sh.movie_id
INNER JOIN screen sc  ON sc.screen_id  = sh.screen_id;
