import datetime
from unittest.mock import patch

from cron.update_lunch import add_events

def test_read_lunches():
    with patch("cron.update_lunch.write_event_to_db") as mock:
        ICS_PATH = "data/test_lunch.ics"
        fake_response = open(ICS_PATH, encoding="utf-8").read()
        add_events(fake_response)

        assert mock.call_count == 1  # summary() == "Cheese Manicotti"
        event = mock.call_args[0][1]
        assert event.summary == "Cheese Manicotti"
        assert event.day == datetime.date(2019, 10, 7)
        assert event.description == [
            "Cheese Manicotti with Meat Sauce\\, Side Salad\\, and Bread Stick",
            "Vegetarian Option: Eggplant Lasagna",
        ]
