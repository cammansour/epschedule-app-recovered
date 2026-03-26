import json
import unittest

from app import app, init_app

with open("data/test_schedule.json", "r") as f:
    TEST_SCHEDULES = json.load(f)

TEST_MASTER_SCHEDULE = [
    {
        "2020-09-01": "Remote A-D_Rem",
        "2020-11-30": "End of Fall Term",
        "2021-03-30": "End of Winter Term",
    }
]

TEST_TEACHER = "jbriggs"
TEST_STUDENT = "bbison"
TEST_STUDENT_NO_PIC = "aaardvark"

class FakeKey:
    def __init__(self, name):
        self.name = name

class FakeEntity:
    def __init__(self, key):
        self.key = key

    def get(self, prop):
        return self.key.name != TEST_STUDENT_NO_PIC

    def items(self):
        return {}

class FakeDatastore:
    def key(self, a, b):
        return FakeKey(b)

    def get(self, key):
        return FakeEntity(key)

    def get_multi(self, keys):
        return [FakeEntity(key) for key in keys]

TEST_CONFIG = {
    "TESTING": True,
    "SECRET_KEY": bytes("test-key", "ascii"),
    "TOKEN": "test-token",
    "SCHEDULES": TEST_SCHEDULES,
    "MASTER_SCHEDULE": TEST_MASTER_SCHEDULE,
    "DATASTORE": FakeDatastore(),
}

API_ENDPOINTS = [
    "/student/aaardvark",
    "/class/a",
    "/period/a",
    "/search/aaardvark",
]

class NoAuthTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        init_app(TEST_CONFIG)

    def setUp(self):
        self.client = app.test_client()

    def test_main_login_response(self):
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertIn("Sign in to EPSchedule", str(response.data))

    def test_api_unauthorized(self):
        for endpoint in API_ENDPOINTS:
            response = self.client.get(endpoint)
            self.assertEqual(response.status_code, 403)

    def test_login(self):
        self.client.set_cookie(
            key="token", value='{"email": "bbison@eastsideprep.org"}'
        )
        test_username = "bbison"
        with self.client as c:
            response = c.get("/")
            with c.session_transaction() as sess:
                self.assertEqual(sess["username"], test_username)

        self.assertEqual(response.status_code, 200)

AUTHENTICATED_USER = "bbison"

class AuthenticatedTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        init_app(TEST_CONFIG)

    def setUp(self):
        self.client = app.test_client()
        with self.client.session_transaction() as sess:
            sess["username"] = AUTHENTICATED_USER

    def check_photo_url(self, url):
        self.assertTrue(
            url.startswith("https://epschedule-avatars.storage.googleapis.com/")
        )

class TestStudentEndpoint(AuthenticatedTest):
    """Tests for the /student endpoint."""

    def check_username(self, username):
        response = self.client.get(f"/student/{username}")
        self.assertEqual(response.status_code, 200)
        obj = json.loads(response.data)
        self.assertEqual(obj["username"], username)
        self.assertIn(obj["username"], obj["email"])
        self.assertEqual(len(obj["classes"]), 3)

        for trimester in obj["classes"]:
            self.assertGreaterEqual(len(trimester), 8)

        return obj

    def test_get_student(self):
        teacher_obj = self.check_username(TEST_TEACHER)
        student_obj = self.check_username(TEST_STUDENT)

        self.assertIsNone(teacher_obj["grade"])
        self.assertIsNone(teacher_obj["gradyear"])

        self.assertGreaterEqual(student_obj["grade"], 5)
        self.assertGreaterEqual(student_obj["gradyear"], 2020)

    def test_has_photo(self):
        teacher_obj = self.check_username(TEST_TEACHER)
        self.check_photo_url(teacher_obj["photo_url"])

    def test_urls_showing_up(self):
        student_obj = self.check_username(TEST_STUDENT_NO_PIC)
        self.assertEqual(student_obj["photo_url"], "/static/images/placeholder.png")

    def test_student_pics_showing_up(self):
        student_obj = self.check_username(TEST_STUDENT)
        self.assertNotEqual(student_obj["photo_url"], "/static/images/placeholder.png")

TEST_SEARCH = "b"

class TestSearchEndpoint(AuthenticatedTest):
    """Tests for the /search endpoint."""

    def test_search_endpoint(self):
        response = self.client.get("/search/{}".format(TEST_SEARCH))
        self.assertEqual(response.status_code, 200)
        results = json.loads(response.data)

        self.assertEqual(len(results), 2)
        for result in results:
            self.assertIn(TEST_SEARCH.lower(), result["name"].lower())

class TestClassEndpoint(AuthenticatedTest):
    """Tests for the /class endpoint."""

    def test_class_endpoint(self):
        response = self.client.get("/class/a?term_id=1")
        self.assertEqual(response.status_code, 200)
        _ = json.loads(response.data)

    def test_urls_inclass(self):
        response = self.client.get("/class/h?term_id=1")
        results = json.loads(response.data)
        students = results["students"]
        found_student = None
        for student in students:
            if student["username"] == TEST_STUDENT_NO_PIC:
                found_student = student
        self.assertNotEqual(found_student, None)
        self.assertEqual(
            found_student["photo_url"], "/static/images/placeholder_small.png"
        )

class TestPeriodEndpoint(AuthenticatedTest):
    """Tests for the /period endpoint."""

    def test_period_endpoint(self):
        response = self.client.get("/period/a")
        self.assertEqual(response.status_code, 200)
        results = json.loads(response.data)
        self.assertEqual(results["period"], "A")
        self.assertGreaterEqual(results["term_id"], 0)
        self.assertLessEqual(results["term_id"], 2)

class TestLogout(AuthenticatedTest):
    def test_logout(self):
        response = self.client.post("/logout")
        self.assertEqual(response.status_code, 200)
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertIn("Sign in to EPSchedule", str(response.data))

if __name__ == "__main__":
    unittest.main()
