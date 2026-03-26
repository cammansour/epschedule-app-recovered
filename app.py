VERSION = "1.32.54"  # Massive UI update/complete backend rework is the first number, noticable bug fixes or UI updates are middle number, and any update that doesn't make that big of a difference, even if it just adds a backend thing, is the last number.

import copy
import datetime
import json
import os
import re

import google.oauth2.id_token
from flask import Flask, abort, make_response, render_template, request, session
from github import Github as gh
from google.auth.transport import requests
from google.cloud import datastore, secretmanager, storage

from cron.photos import crawl_photos, hash_username
from cron.schedules import crawl_schedules
from cron.update_lunch import get_lunches_since_date, read_lunches

app = Flask(__name__)

verify_firebase_token = None
datastore_client = None
SCHEDULE_INFO = None
DAYS = None
TERM_STARTS = []
GITHUB_COMMITS = None
NUM_COMMITS = 50

def init_app(test_config=None):
    """Initialize the app and set up global variables."""
    global verify_firebase_token
    global datastore_client
    global SCHEDULE_INFO
    global DAYS
    global TERM_STARTS
    global GITHUB_COMMITS
    app.permanent_session_lifetime = datetime.timedelta(days=3650)
    if test_config is None:
        if "GOOGLE_APPLICATION_CREDENTIALS" not in os.environ:
            os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = "service_account.json"

        secret_client = secretmanager.SecretManagerServiceClient()
        app.secret_key = secret_client.access_secret_version(
            request={"name": "projects/epschedule-v2/secrets/session_key/versions/1"}
        ).payload.data

        verify_firebase_token = (
            lambda token: google.oauth2.id_token.verify_firebase_token(
                token, requests.Request()
            )
        )

        storage_client = storage.Client()
        data_bucket = storage_client.bucket("epschedule-data")
        SCHEDULE_INFO = json.loads(
            data_bucket.blob("schedules.json").download_as_string()
        )
        DAYS = json.loads(data_bucket.blob("master_schedule.json").download_as_string())
        GITHUB_COMMITS = get_latest_github_commits()
        datastore_client = datastore.Client()
    else:
        app.config.from_mapping(test_config)

        def verify_firebase_token(token):
            return json.loads(token)

        datastore_client = app.config["DATASTORE"]
        SCHEDULE_INFO = app.config["SCHEDULES"]
        DAYS = app.config["MASTER_SCHEDULE"]
        GITHUB_COMMITS = []
    TERM_STARTS = get_term_starts(DAYS[0])

def get_term_starts(days):
    """Return a list of datetime objects for the start of each trimester."""
    return [
        find_day(days, ".*"),
        find_day(days, ".*End.*Fall Term") + datetime.timedelta(days=1),
        find_day(days, ".*End.*Winter Term") + datetime.timedelta(days=1),
    ]

def find_day(days, regex):
    """Find the first day that matches the given regex"""
    for day in days:
        if re.match(regex, days[day]):
            return datetime.datetime.strptime(day, "%Y-%m-%d").date()
    assert False, f"No day matched {regex}"

def get_term_id():
    """Return the current trimester index (fall=0, winter=1, spring=2)"""
    today = datetime.datetime.now().date()
    for i in range(len(TERM_STARTS) - 1):
        if today < TERM_STARTS[i + 1]:
            return i
    return 2

def username_to_email(username):
    return username + "@eastsideprep.org"

def is_admin():
    """Return True if the current session user is an admin.

    Admin users are hard-coded in a few places in the original code. Centralize
    the check so all admin-related behavior is consistent.
    """
    try:
        return session.get("username") in ("cwest", "ajosan", "rpudipeddi")
    except Exception:
        return False

def is_teacher_schedule(schedule):
    if schedule:
        if schedule.get("grade"):
            return not schedule["grade"]
        else:
            return True
    return False

def get_schedule_data():
    return SCHEDULE_INFO

def get_schedule(username):
    schedules = get_schedule_data()
    if username not in schedules:
        return None
    return schedules[username]

def gen_photo_url(username, icon=False):
    return "https://epschedule-avatars.storage.googleapis.com/{}".format(
        hash_username(app.secret_key, username, icon)
    )

def photo_exists(username, icon=False):
    """Return True if the user's avatar is present in storage or marked in datastore.

    Priority:
    - If a datastore entry exists and exposes a has_photo property (used in tests),
      honor that.
    - Else, if a storage client is configured, check whether the blob exists.
    - Otherwise, assume True to avoid hiding photos in environments we can't check.
    """
    try:
        entry = get_database_entry(username)
    except Exception:
        entry = None

    if entry:
        try:
            has_photo = entry.get("has_photo")
        except Exception:
            has_photo = None
        if has_photo is not None:
            return bool(has_photo)

    try:
        if datastore_client is not None:
            sc = globals().get("storage_client", None)
            if sc:
                blob_name = hash_username(app.secret_key, username, icon)
                bucket = sc.bucket("epschedule-avatars")
                blob = bucket.blob(blob_name)
                try:
                    return blob.exists(sc)
                except Exception:
                    pass
    except Exception:
        pass

    return True

def gen_login_response():
    template = make_response(render_template("login.html"))
    session.pop("username", None)
    template.set_cookie("token", "", expires=0)
    return template

def get_user_key(username):
    return datastore_client.key("user", username)

def get_database_entry(username):
    return datastore_client.get(get_user_key(username))

def get_database_entries(usernames):
    keys = [get_user_key(x) for x in usernames]
    return datastore_client.get_multi(keys)

@app.route("/")
def main():

    token = request.cookies.get("token")
    if token:
        try:
            claims = verify_firebase_token(token)
            session.permanent = True
            session["username"] = claims["email"].split("@")[0]

            key = get_user_key(session["username"])
            if not datastore_client.get(key):
                user = datastore.Entity(key=key)
                user.update(
                    {
                        "joined": datetime.datetime.utcnow(),
                        "share_photo": True,
                    }
                )
                datastore_client.put(user)

        except ValueError:
            return gen_login_response()

    elif "username" not in session:
        return gen_login_response()

    lunches = get_lunches_since_date(datetime.date.today() - datetime.timedelta(28))

    db_entry = get_database_entry(session["username"])
    response = make_response(
        render_template(
            "index.html",
            schedule=json.dumps(get_schedule(session["username"])),
            days=json.dumps(DAYS),
            components="static/components.html",
            lunches=lunches,
            term_starts=json.dumps([d.isoformat() for d in TERM_STARTS]),
            latest_commits=json.dumps(GITHUB_COMMITS),
            admin=is_admin(),
            share_photo=str(
                True if db_entry is None else dict(db_entry.items()).get("share_photo")
            ).lower(),
            version=VERSION,
            username=session.get("username"),
        )
    )
    response.set_cookie("token", "", expires=0)
    return response

@app.route("/class/<period>")
def handle_class(period):
    if "username" not in session:
        abort(403)

    schedule = get_schedule(session["username"])
    try:
        term = int(request.args["term_id"])
        class_name = next(
            (
                c
                for c in schedule["classes"][term]
                if c["period"].lower() == period.lower()
            )
        )
    except:
        abort(404)

    class_schedule = get_class_schedule(class_name, term)
    return json.dumps(class_schedule)

def is_same_class(a, b):
    return (
        a["teacher_username"] == b["teacher_username"]
        and a["period"] == b["period"]
        and a["name"] == b["name"]
    )

def get_class_schedule(user_class, term_id):
    result = {
        "period": user_class["period"],
        "teacher": user_class["teacher_username"],
        "term_id": term_id,
        "students": [],
    }
    user_is_teacher = is_teacher_schedule(get_schedule(session["username"]))
    for schedule in get_schedule_data().values():
        for classobj in schedule["classes"][term_id]:
            if is_same_class(user_class, classobj):
                if (not is_teacher_schedule(schedule)) or classobj[
                    "name"
                ] == "Free Period":
                    priv_settings = {"share_photo": False}
                    priv_obj = get_database_entry(schedule["username"])
                    if priv_obj:
                        if dict(priv_obj.items()).get("share_photo"):
                            priv_settings["share_photo"] = True
                    student = {
                        "firstname": get_first_name(schedule),
                        "lastname": schedule["lastname"],
                        "grade": schedule["grade"],
                        "username": schedule["username"],
                        "email": username_to_email(schedule["username"]),
                        "photo_url": (
                            gen_photo_url(schedule["username"], True)
                            if (
                                priv_settings["share_photo"]
                                or is_admin()
                                or session["username"] == schedule["username"]
                                or user_is_teacher
                            )
                            else "/static/images/placeholder_small.png"
                        ),
                    }
                    result["students"].append(student)

    result["students"] = sorted(
        sorted(result["students"], key=lambda s: s["firstname"]),
        key=lambda s: str(s["grade"]),
    )

    return result

@app.route("/student/<target_user>")
def handle_user(target_user):
    if "username" not in session:
        abort(403)

    user_schedule = get_schedule(session["username"])
    target_schedule = get_schedule(target_user)
    if user_schedule is None or target_schedule is None:
        abort(404)
    priv_settings = {"share_photo": False}
    if session["username"] == target_user:
        priv_settings = {"share_photo": True}
    elif is_teacher_schedule(target_schedule):
        priv_settings = {"share_photo": True}
    elif is_teacher_schedule(user_schedule):
        priv_settings = {"share_photo": True}
    else:
        priv_obj = get_database_entry(target_user)
        if priv_obj:
            if dict(priv_obj.items()).get("share_photo"):
                priv_settings["share_photo"] = True
    if is_admin():
        priv_settings = {"share_photo": True}

    target_schedule["email"] = username_to_email(target_user)

    if priv_settings["share_photo"]:
        target_schedule["photo_url"] = gen_photo_url(target_user, False)
    else:
        target_schedule["photo_url"] = "/static/images/placeholder.png"
    return json.dumps(target_schedule)

def sanitize_schedule(orig_schedule, user_schedule):
    schedule = copy.deepcopy(orig_schedule)
    for i in range(0, len(schedule["classes"])):
        for k in range(0, len(schedule["classes"][i])):
            if not schedule["classes"][i][k] in user_schedule["classes"][i]:
                schedule["classes"][i][k] = sanitize_class(schedule["classes"][i][k])

    return schedule

def sanitize_class(orig_class_obj):
    class_obj = orig_class_obj.copy()
    study_halls = ["Study Hall", "GSH", "Free Period"]

    if class_obj["name"] in study_halls:
        class_obj["name"] = "Free Period"
    else:
        class_obj["name"] = "Hidden"
        class_obj["teacher_username"] = "Hidden"
        class_obj["department"] = "Hidden"

    class_obj["teacher"] = ""
    class_obj["room"] = ""

    return class_obj  # Return the class object

@app.route("/period/<period>")
def handle_period(period):
    if "username" not in session:
        abort(403)

    try:
        term = int(request.args["term_id"])
    except:
        term = get_term_id()
    schedule = get_schedule(session["username"])
    grade_range = get_grade_range(schedule["grade"])
    available = get_available(period, term, grade_range)
    current_class = pop_current_class(available, schedule, term, period)

    return json.dumps(
        {
            "period": period.upper(),
            "term_id": term,
            "freerooms": get_free_rooms(period, term),
            "classes": [available] * 3,  # TODO add support for other terms
            "currentclass": current_class,
            "altperiods": None,  # TODO add this in UI
        }
    )

def get_free_rooms(period, term):
    free = set()
    occupied = set()
    for schedule in get_schedule_data().values():
        if is_teacher_schedule(schedule):
            continue
        for clss in schedule["classes"][term]:
            if clss["period"] == period.upper():
                occupied.add(clss["room"])
            else:
                free.add(clss["room"])
    return list(free - occupied)

def get_grade_range(grade):
    if not grade:
        return None
    elif grade <= 8:  # Middle school
        return range(5, 9)
    else:
        return range(9, 13)

def get_available(period, term, grades):
    available = {}
    for schedule in get_schedule_data().values():
        c = get_class_by_period(schedule["classes"][term], period)
        key = c["teacher_username"]
        if not key:  # Skip free periods
            continue
        if key in available and not is_teacher_schedule(schedule):
            available[key]["students"] += 1
        elif schedule["grade"] in grades:
            available[key] = copy.copy(c)
            available[key]["students"] = 1
    return list(available.values())

def pop_current_class(available, schedule, term, period):
    current_class = get_class_by_period(schedule["classes"][term], period)
    for c in available:
        if c["teacher_username"] == current_class["teacher_username"]:
            available.remove(c)
            return c

def get_class_by_period(schedule, period):
    for c in schedule:
        if c["period"].lower() == period.lower():
            return c

@app.route("/privacy", methods=["GET", "POST"])
def handle_settings():
    if "username" not in session:
        abort(403)
    user = get_database_entry(session["username"])
    if request.method == "GET":
        user_privacy_dict_raw = dict(user.items())
        user_privacy_dict = {"share_photo": user_privacy_dict_raw["share_photo"]}
        return json.dumps(user_privacy_dict)

    elif request.method == "POST":
        user.update(
            {
                "share_photo": request.form["share_photo"] == "true",
            }
        )
        datastore_client.put(user)
        return json.dumps({})

@app.route("/me")
def handle_me():
    """Return the current logged-in user's info and schedule - for mobile apps."""
    if "username" not in session:
        abort(403)
    
    username = session["username"]
    schedule = get_schedule(username)
    if schedule is None:
        abort(404)
    
    result = {
        "username": username,
        "schedule": schedule,
        "email": username_to_email(username),
        "photo_url": gen_photo_url(username, False),
    }
    return json.dumps(result)

@app.route("/api/master_schedule")
def handle_master_schedule():
    """Return the master schedule (days) for mobile apps."""
    if "username" not in session:
        abort(403)
    
    return json.dumps(DAYS[0] if isinstance(DAYS, (list, tuple)) else DAYS)

@app.route("/api/term_starts")
def handle_term_starts():
    """Return the term start dates for mobile apps."""
    if "username" not in session:
        abort(403)
    
    return json.dumps([d.isoformat() for d in TERM_STARTS])

@app.route("/api/pass/<target_username>")
def handle_pass_download(target_username):
    """Download a student ID pass (.pkpass file) from storage."""
    if "username" not in session:
        abort(403)
    
    if session["username"] != target_username and not is_admin():
        abort(403)
    
    try:
        storage_client = storage.Client()
        data_bucket = storage_client.bucket("epschedule-data")
        
        blob_name = f"passes/{target_username}.pkpass"
        blob = data_bucket.blob(blob_name)
        
        if not blob.exists():
            abort(404)
        
        pass_data = blob.download_as_bytes()
        
        response = make_response(pass_data)
        response.headers["Content-Type"] = "application/vnd.apple.pkpass"
        response.headers["Content-Disposition"] = f'attachment; filename="{target_username}.pkpass"'
        return response
    except Exception as e:
        print(f"Error serving pass for {target_username}: {e}")
        abort(500)

@app.route("/search/<keyword>")
def handle_search(keyword):
    if "username" not in session:
        abort(403)

    results = []
    for schedule in get_schedule_data().values():
        test_keyword = get_first_name(schedule) + " " + schedule["lastname"]
        if keyword.lower() in test_keyword.lower():
            results.append({"name": test_keyword, "username": schedule["username"]})
            if len(results) >= 5:  # Allow up to 5 results
                break
    return json.dumps(results)

def get_first_name(schedule):
    return schedule.get("preferred_name") or schedule["firstname"]

def get_latest_github_commits():
    secret_client = secretmanager.SecretManagerServiceClient()
    gh_token = secret_client.access_secret_version(
        request={"name": "projects/epschedule-v2/secrets/gh_token/versions/1"}
    ).payload.data
    g = gh(gh_token.decode("utf-8"))
    repo = g.get_repo("EastsidePreparatorySchool/epschedule")
    commitsArr = repo.get_commits()
    result = []  # initialize array for it
    for repo_num in range(
        commitsArr.totalCount
        if not NUM_COMMITS
        else min(NUM_COMMITS, commitsArr.totalCount)
    ):
        commit_name = commitsArr[repo_num].commit.message.split("\n")[0]
        commit_author = commitsArr[repo_num].commit.author.name
        raw_date = str(commitsArr[repo_num].commit.author.date)
        commit_url = commitsArr[repo_num].html_url
        result.append(
            {
                "name": commit_name,
                "author": commit_author,
                "date": raw_date,
                "url": commit_url,
            }
        )
    return result

@app.route("/logout", methods=["POST"])
def handle_sign_out():
    session.clear()
    return json.dumps({})

@app.route("/cron/schedules")
def handle_cron_schedules():
    crawl_schedules()
    return "OK"

@app.route("/cron/photos")
def handle_cron_photos():
    crawl_photos()
    return "OK"

@app.route("/cron/update_lunch")
def handle_cron_lunches():
    read_lunches()
    return "OK"
