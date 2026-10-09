"""CineSphere – Cinema Management & Booking System  (run with:  streamlit run app.py)"""
import logging
from datetime import datetime

import streamlit as st

import database as db
from utils import helpers as h
from utils import styles
from views import (about, booking, bookings, cancellations, concessions, dashboard, database_viewer,
                   movies, payments, reports, scheduling, screens, seats, ticket)

st.set_page_config(page_title="CineSphere", page_icon="🎬", layout="wide", initial_sidebar_state="expanded")
styles.inject_css()

# page name -> (icon, render function)
PAGES = {
    "Dashboard": ("📊", dashboard.render),
    "Movies": ("🎬", movies.render),
    "Screens": ("🏛️", screens.render),
    "Show Scheduling": ("🗓️", scheduling.render),
    "Seat Availability": ("💺", seats.render),
    "Customer Booking": ("🎟️", booking.render),
    "Bookings": ("📒", bookings.render),
    "Ticket": ("🎫", ticket.render),
    "Concessions": ("🍿", concessions.render),
    "Payments": ("💳", payments.render),
    "Cancellations & Refunds": ("↩️", cancellations.render),
    "Reports & Analytics": ("📈", reports.render),
    "Database Viewer": ("🗄️", database_viewer.render),
    "About / System Information": ("ℹ️", about.render),
}
# Edit this mapping to change what each role can open (e.g. add "Customer Booking" for Staff).
ROLE_PAGES = {
    "Admin": list(PAGES),
    "Staff": ["Dashboard", "Bookings", "Seat Availability", "Ticket", "Concessions", "Payments"],
}


@st.cache_resource(show_spinner="Setting up the database…")
def bootstrap():
    return db.init_db()  # creates tables/views/triggers and seeds demo data on first run


def login_screen():
    _, mid, _ = st.columns([1, 1.2, 1])
    with mid:
        st.markdown('<div class="cs-header" style="text-align:center"><h1>🎬 CineSphere</h1>'
                    '<p>Cinema Management &amp; Booking System</p></div>', unsafe_allow_html=True)
        with st.container(border=True):
            st.markdown("#### Sign in")
            with st.form("login"):
                username = st.text_input("Username", placeholder="admin or staff")
                password = st.text_input("Password", type="password")
                submitted = st.form_submit_button("Sign in", type="primary")
            if submitted:
                user = db.authenticate(username, password)
                if user:
                    st.session_state["user"] = user
                    st.session_state["nav"] = "Dashboard"
                    st.rerun()
                st.error("Invalid username or password.", icon="❌")
            st.caption("Demo accounts (academic prototype) – Admin: `admin / admin123` · Staff: `staff / staff123`")


def sidebar(user):
    allowed = ROLE_PAGES[user["role"]]
    with st.sidebar:
        st.markdown('<div class="cs-logo">🎬 CineSphere<small>Smart Cinema Operations, Booking &amp; Analytics Platform</small></div>',
                    unsafe_allow_html=True)
        st.markdown(f'{styles.badge(user["role"], "gold")} &nbsp; <span style="color:#9aa6c4;font-size:.85rem">{user["full_name"]}</span>',
                    unsafe_allow_html=True)
        st.divider()
        if st.session_state.get("nav") not in allowed:
            st.session_state["nav"] = allowed[0]
        page = st.radio("Navigation", allowed, key="nav", label_visibility="collapsed",
                        format_func=lambda p: f"{PAGES[p][0]}  {p}")
        st.divider()
        st.caption(f"📅 {datetime.now():%A, %d %B %Y}")
        if st.button("Logout"):
            for k in list(st.session_state.keys()):
                del st.session_state[k]
            st.rerun()
    return page


def main():
    seeded = bootstrap()
    db.refresh_show_statuses()
    if seeded and not st.session_state.get("_init_toast"):
        st.session_state["_init_toast"] = True
        st.toast("Database initialized successfully", icon="✅")
    user = st.session_state.get("user")
    if not user:
        login_screen()
        return
    page = sidebar(user)
    try:
        PAGES[page][1]()
    except Exception:  # never show a raw traceback to the user
        logging.exception("Unhandled error on page %s", page)
        st.error("Something went wrong while loading this page. Please try again or choose another page.", icon="❌")


main()
