import datetime
import logging
import os

import requests
from google.cloud import ndb

if "GOOGLE_APPLICATION_CREDENTIALS" not in os.environ:
    os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = "service_account.json"

TIME_FORMAT = "%Y%m%dT%H%M%S"
LUNCH_URL = "http://www.eastsideprep.org/?post_type=tribe_events&ical=1&eventDisplay=list&tribe_events_cat=lunch"

class Lunch(ndb.Model):
    summary = ndb.StringProperty(required=True)
    description = ndb.StringProperty(repeated=True)
    day = ndb.DateProperty(required=True)

    @classmethod
    def query_with_time_constraint(cls, earliest_lunch):
        return cls.query().filter(Lunch.day >= earliest_lunch)

def parse_events(lines):  # lines is a list of all lines of text in the whole file
    in_event = False  # Whether the current line is in an event
    properties = {}  # When properties are discovered, they will be stuffed in here
    events = []  # The list of all properties objects
    last_prop_name = None
    for line in lines:
        if line == "BEGIN:VEVENT":
            in_event = True
        elif line == "END:VEVENT":
            in_event = False
            events.append(properties)
            properties = {}
        elif in_event:
            if (
                line[0] == " "
            ):  # If the current line is a continuation of the previous line
                properties[last_prop_name] += line[1:]
            else:  # If it is the start of a normal line
                colon_separated_values = line.split(":", 1)

                last_prop_name = colon_separated_values[0].split(";")[0]

                properties[last_prop_name] = colon_separated_values[1]
    return events

def save_events(events, dry_run=False, verbose=False):
    client = ndb.Client()
    for event in events:
        try:
            date = datetime.datetime.strptime(event["DTSTART"], TIME_FORMAT).date()
        except ValueError:
            date = datetime.datetime.strptime(event["DTSTART"], "%Y%m%d").date()

        summary = event["SUMMARY"]

        desc = event["DESCRIPTION"]

        lines = desc.split("\\n")[:2]
        """['[vc_row padding_top=”0px” padding_bottom=”0px”][vc_column fade_animation_offset=”45px”]With Mashed Potato and Fresh Veggie', 'Vegetarian Option: Seitan Chimichurri']  
            2023-11-30: Flat Iron Chimichurri
                        With Mashed Potato and Fresh Veggie
                        Vegetarian Option: Seitan Chimichurri"""
        description = [
            line.replace(
                "[vc_row padding_top=”0px” padding_bottom=”0px”][vc_column fade_animation_offset=”45px”]",
                "",
            ).strip()
            for line in lines
        ]

        print(f"{date}: {summary}")
        if verbose:
            for line in description:
                print("           ", line)
        if not dry_run:
            entry = Lunch(summary=summary, description=description, day=date)
            write_event_to_db(client, entry)

def write_event_to_db(client, entry):  # Places a single entry into the db
    with client.context():
        lunches_for_date = Lunch.query(Lunch.day == entry.day)

        for lunch in lunches_for_date:
            logging.info(str(entry.day) + " is already in the DB")
            lunch.key.delete()  # Delete the existing ndb entity

        logging.info(f"Adding lunch entry to DB: {str(entry)}")
        entry.put()

def add_events(response_text, dry_run=False, verbose=False):
    text = response_text
    lines = text.splitlines()
    events = parse_events(lines)

    save_events(events, dry_run, verbose)

def read_lunches(dry_run=False, verbose=False):  # Update the database with new lunches
    response = requests.get(LUNCH_URL)
    add_events(response.text, dry_run, verbose)

def get_lunches_since_date(date):
    client = ndb.Client()
    with client.context():
        earliest_lunch = date
        lunch_objs = []
        for lunch_obj in Lunch.query_with_time_constraint(earliest_lunch):
            cleaned_description = (
                []
            )  # the desc after it is cleaned of escape characters and new lines
            for description_section in lunch_obj.description:
                if not (
                    description_section == ""
                    or description_section == " "
                    or description_section == False
                ):  # eliminates a section if it is empty or just a space
                    cleaned_description.append(
                        description_section.replace("\\,", ",")
                        .replace("\n", "")
                        .replace("&amp\\;", "&")
                        .replace(
                            "Click here for meal account and food services details", ""
                        )
                    )

            obj = {
                "summary": lunch_obj.summary.replace(
                    "\\,", ","
                ),  # deletes all annoying escape character backslashes
                "description": cleaned_description,
                "day": lunch_obj.day.day,
                "month": lunch_obj.day.month,
                "year": lunch_obj.day.year,
            }
            lunch_objs.append(obj)

    return lunch_objs
