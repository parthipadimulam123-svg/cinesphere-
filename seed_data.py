"""Realistic demo data. Dates are relative to 'today' so the dashboard is always populated."""
import random
from datetime import datetime, timedelta

import database as db

MOVIES = [  # title, genre, minutes, language, rating, release offset (days), status
    ("Shadow Protocol", "Action", 128, "English", "PG-13", -20, "Now Showing"),
    ("Beyond the Stars", "Sci-Fi", 148, "English", "PG", -35, "Now Showing"),
    ("The Last Horizon", "Adventure", 135, "English", "PG-13", -14, "Now Showing"),
    ("Midnight Runway", "Drama", 112, "Hindi", "R", -25, "Now Showing"),
    ("Echoes of Tomorrow", "Sci-Fi", 124, "Telugu", "PG-13", -10, "Now Showing"),
    ("Kingdom of Ember", "Fantasy", 142, "English", "PG", -18, "Now Showing"),
    ("Ocean Quest", "Animation", 98, "English", "G", -30, "Now Showing"),
    ("Silent Code", "Thriller", 116, "English", "R", 14, "Coming Soon"),
]
SCREENS = [  # name, type, rows, seats per row, premium rows, vip rows, base price
    ("Screen 1", "IMAX", 8, 12, 2, 1, 16.0),
    ("Screen 2", "Standard", 6, 10, 2, 1, 11.0),
    ("Screen 3", "Premium", 5, 8, 2, 0, 14.0),
    ("Screen 4", "VIP", 4, 6, 0, 4, 22.0),
]
CUSTOMERS = ["Aarav Sharma", "Priya Nair", "Rohan Mehta", "Sneha Reddy", "Vikram Singh", "Ananya Iyer", "Karthik Rao",
             "Meera Das", "Arjun Patel", "Divya Menon", "Imran Khan", "Lakshmi Narayan", "Sanjay Gupta",
             "Neha Kapoor", "Rahul Verma"]
ITEMS = [  # name, category, price, stock
    ("Popcorn", "Snacks", 6.50, 400), ("Nachos", "Snacks", 7.50, 250), ("Hot Dog", "Snacks", 6.00, 200),
    ("Soft Drink", "Beverages", 4.50, 500), ("Water", "Beverages", 2.50, 500),
    ("Chocolate", "Sweets", 3.50, 300), ("Ice Cream", "Desserts", 4.00, 250), ("Combo Meal", "Combos", 14.00, 300),
]
SLOTS = ["10:00", "13:30", "17:00", "20:30"]
REASONS = ["Change of plans", "Schedule clash", "Unwell", "Booked wrong show", "Travel delay"]


def _pick_group(rows, taken, size, rng):
    """Find `size` adjacent free seats in a random row."""
    order = list(range(len(rows)))
    rng.shuffle(order)
    for ri in order:
        row = rows[ri]
        starts = [i for i in range(len(row) - size + 1) if all(s not in taken for s in row[i:i + size])]
        if starts:
            i = rng.choice(starts)
            return row[i:i + size]
    return None


def seed_database():
    rng = random.Random(42)
    now = datetime.now()
    today = now.date()

    db.create_user("admin", "admin123", "Admin", "Alex Morgan (Administrator)")
    db.create_user("staff", "staff123", "Staff", "Sam Carter (Box Office)")

    for t, g, d, lang, r, off, st in MOVIES:
        db.save_movie({"title": t, "genre": g, "duration_minutes": d, "language": lang, "rating": r,
                       "release_date": (today + timedelta(days=off)).isoformat(), "status": st})
    prices = {}
    for name, typ, rows, per, prem, vip, price in SCREENS:
        prices[db.create_screen(name, typ, rows, per, prem, vip)] = price
    customer_ids = [db.add_customer(n, f"{n.lower().replace(' ', '.')}@example.com",
                                    f"+91 98{rng.randint(10000000, 99999999)}") for n in CUSTOMERS]
    for n, c, p, s in ITEMS:
        db.execute("INSERT INTO concession_item(item_name, category, unit_price, stock_quantity) VALUES (?,?,?,?)", (n, c, p, s))

    # ---- shows: 8 days (4 past, today, 3 future), two slots per screen per day
    movie_ids = [m["movie_id"] for m in db.query_all("SELECT movie_id FROM movie WHERE status = 'Now Showing'")]
    for offset in range(-4, 4):
        day = (today + timedelta(days=offset)).isoformat()
        for screen_id, base in prices.items():
            for slot in sorted(rng.sample(SLOTS, 2)):
                price = base + (2 if slot >= "17:00" else 0)
                db.add_show(rng.choice(movie_ids), screen_id, day, slot, price, 15, allow_past=True)
    db.refresh_show_statuses()

    # ---- seat layout cache
    seat_rows = {}
    for sc in db.query_all("SELECT screen_id FROM screen"):
        grid = {}
        for s in db.query_all("SELECT seat_id, row_label FROM seat WHERE screen_id = ? ORDER BY row_label, seat_number", (sc["screen_id"],)):
            grid.setdefault(s["row_label"], []).append(s["seat_id"])
        seat_rows[sc["screen_id"]] = list(grid.values())

    shows = db.query_all("""SELECT sh.show_id, sh.screen_id, sh.show_date, sh.start_time, sc.capacity
                            FROM show sh INNER JOIN screen sc ON sc.screen_id = sh.screen_id ORDER BY sh.show_id""")
    taken = {s["show_id"]: set() for s in shows}
    methods = ["Card"] * 5 + ["Digital Wallet"] * 3 + ["Cash"] * 2

    def start_of(sh):
        return datetime.strptime(f"{sh['show_date']} {sh['start_time']}", "%Y-%m-%d %H:%M")

    for sh in shows:
        start = start_of(sh)
        near = (start.date() - today).days <= 1
        target = int(sh["capacity"] * (rng.uniform(0.25, 0.85) if near else rng.uniform(0.0, 0.4)))
        if rng.random() < 0.1:
            target = 0
        sold = 0
        while sold < target:
            group = _pick_group(seat_rows[sh["screen_id"]], taken[sh["show_id"]], min(rng.choice([1, 2, 3, 4, 4, 5, 6]), target - sold), rng)
            if not group:
                break
            latest = min(now, start - timedelta(hours=1))
            when = latest - (timedelta(minutes=rng.uniform(5, 300)) if rng.random() < 0.3 else timedelta(hours=rng.uniform(1, 96)))
            db.create_booking(rng.choice(customer_ids), sh["show_id"], group, rng.choice(methods), booking_dt=when, allow_past=True)
            taken[sh["show_id"]].update(group)
            sold += len(group)

    # ---- pending / failed payments on upcoming shows (to demonstrate every payment status)
    future = [s for s in shows if start_of(s) > now + timedelta(hours=3)]
    for status in ("Pending", "Pending", "Failed"):
        sh = rng.choice(future)
        group = _pick_group(seat_rows[sh["screen_id"]], taken[sh["show_id"]], 2, rng)
        if group:
            db.create_booking(rng.choice(customer_ids), sh["show_id"], group, rng.choice(["Card", "Digital Wallet"]),
                              payment_status=status, booking_dt=now - timedelta(minutes=rng.randint(5, 90)))
            if status == "Pending":
                taken[sh["show_id"]].update(group)

    # ---- cancellations covering every refund tier (100%, 75%, 50%, 0%, 100%)
    past = [s for s in shows if -4 <= (start_of(s).date() - today).days <= -1]
    for sh, hours in zip(rng.sample(past, 5), [30, 12, 4, 1, 50]):
        group = _pick_group(seat_rows[sh["screen_id"]], taken[sh["show_id"]], rng.choice([2, 3]), rng)
        if not group:
            continue
        start = start_of(sh)
        res = db.create_booking(rng.choice(customer_ids), sh["show_id"], group, rng.choice(["Card", "Digital Wallet"]),
                                booking_dt=start - timedelta(hours=hours + 5), allow_past=True)
        db.cancel_booking(res["booking_id"], rng.choice(REASONS), now=start - timedelta(hours=hours))

    # ---- concession sales over the last 8 days (several today)
    confirmed = db.query_all("SELECT booking_id, customer_id FROM booking WHERE booking_status = 'Confirmed'")
    item_ids = [i["item_id"] for i in db.query_all("SELECT item_id FROM concession_item")]
    midnight = datetime.combine(today, datetime.min.time())
    for n in range(48):
        if n < 8:
            when = midnight + timedelta(minutes=rng.randint(1, max(2, int((now - midnight).total_seconds() / 60) - 1)))
        else:
            when = now - timedelta(hours=rng.uniform(1, 190))
        cart = {i: rng.randint(1, 3) for i in rng.sample(item_ids, rng.randint(1, 4))}
        link = rng.choice(confirmed) if rng.random() < 0.45 else None
        db.complete_concession_sale(cart, link["customer_id"] if link else None, link["booking_id"] if link else None, when)
    db.refresh_show_statuses()
