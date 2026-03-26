function renderGitHubCommits() {
  let updated = "";
  latestCommits.forEach((commit) => {
    const date = new Date(commit["date"] + " UTC");
    const strDate = date.toLocaleString("en-US");
    updated +=
      '<a class = "GithubLink" href = "' +
      commit["url"] +
      '">' +
      commit["name"] +
      ";<br>" +
      "Committed by " +
      commit["author"] +
      " at " +
      strDate +
      "<br><br>" +
      "</a>";
  });
  document.getElementById("GHUpdateText").innerHTML = updated;
}
function signOut() {
  sendPostMessage("logout", reload);
}
function reload(result) {
  location.reload();
}
function sendPostMessage(location, successFunction, data) {
  xhr = new XMLHttpRequest();
  xhr.onreadystatechange = function () {
    if (xhr.readyState == 4) {
      result = JSON.parse(xhr.responseText);
      if (xhr.status == 200) {
        successFunction(result);
      } else {
        console.log(result.error);
        renderToast(result.error);
      }
    }
  };
  xhr.open("POST", location, true);

  if (typeof data === "undefined") {
    xhr.send(new FormData());
  } else {
    xhr.send(data);
  }
}
function reportBug() {
  window.open("https://forms.office.com/r/rwmhK8xw44");
}
function reportBugOld() {
  window.open("https://github.com/EastsidePreparatorySchool/epschedule/issues");
}

function about() {
  var about = document.getElementById("about");
  about.open();
}

function githubDisplay() {

  var gh = document.getElementById("Github");
  gh.open();
}

function openSettings() {
  var dialog = document.getElementById("dialog");
  dialog.open();
  xhr = new XMLHttpRequest();
  xhr.onreadystatechange = function () {
    if (xhr.readyState == 4 && xhr.status == 200) {
      result = JSON.parse(xhr.responseText);
      if (result.error) {
        console.log(result.error);
      }
    }
  };
  xhr.onload = function () {
    const privacyDataOutput = JSON.parse(xhr.response);

    var sharePhoto = document.getElementById("sharephototoggle");

    sharePhoto.checked = privacyDataOutput.share_photo;
  };

  xhr.open("GET", "privacy", true);
  xhr.send();
}

function submitUpdatePrivacy() {
  var share_photo = document.getElementById("sharephototoggle");
  sendUpdatePrivacyRequest(share_photo.checked);
  document.getElementById("dialog").close();
}

function sendUpdatePrivacyRequest(share_photo) {
  var data = new FormData();
  data.append("share_photo", share_photo);
  xhr = new XMLHttpRequest();
  xhr.onreadystatechange = function () {
    if (xhr.readyState == 4 && xhr.status == 200) {
      result = JSON.parse(xhr.responseText);
      if (!result.error) {
        renderToast("Settings updated!");
      } else {
        console.log(result.error);
        renderToast(result.error);
      }
    }
  };
  xhr.open("POST", "privacy", true);
  xhr.send(data);
}

function scheduleSwiped(evt) {
  if (evt.detail.direction == "left") {
    dateForward();
  } else {
    dateBack();
  }
}

var globalDate = getInitialDate();

function getInitialDate() {
  date = new Date();
  switch (
    date.getDay() // Falling through is intentional here
  ) {
    case 6: // If Saturday, move the date forward twice
      date.setDate(date.getDate() + 2);
      break;
    case 0: // If Sunday, move the date forward once
      date.setDate(date.getDate() + 1);
    default: // Else nothing
      date = date;
  }

  return date;
}
function dateToNextTri() {
  let goToTri = -1; // stores index of trimester you want to go to
  for (let currLooking = 0; currLooking < 3; currLooking++) {
    if (globalDate < triStartDates[currLooking]) {
      goToTri = currLooking; // set it and break
      break;
    }
  }
  if (goToTri == -1) {
    goToTri = 0;
  }

  specifyDate(triStartDates[goToTri]);
}
function specifyDate(goToDate) {
  globalDate = new Date(goToDate);
  globalDate.setDate(globalDate.getDate() + 1);
  if (globalDate.getDay() == 6) {
    globalDate.setDate(globalDate.getDate() + 2); // Skip to Monday
  } else if (globalDate.getDay() == 0) {
    globalDate.setDate(globalDate.getDate() + 1); // Skip to Monday
  }
  console.log(globalDate);
  updateMainSchedule();
}
function dateBack() {
  adjustDate(globalDate, -1);
  updateMainSchedule();
}
function dateForward() {
  adjustDate(globalDate, 1);
  updateMainSchedule();
}
function selectDate() {
  let dateElement = document.getElementById("date");
  splitDate = dateElement.value.split("-");
  globalDate = new Date(splitDate[0], splitDate[1] - 1, splitDate[2]);
  console.log(globalDate);
  updateMainSchedule();
}
function skipToWinter() {
  globalDate.setDate(fallTriEndDate.getDate());
  dateForward();
}
function skipToSpring() {
  globalDate.setDate(wintTriEndDate.getDate());
  dateForward();
}
function copyDate(date) {
  return new Date(date.getTime());
}
function adjustDate(date, delta) {
  date.setDate(date.getDate() + delta);
  if (date.getDay() == 6 && delta == 1) {
    date.setDate(date.getDate() + 2);
  } else if (date.getDay() == 0 && delta == -1) {
    date.setDate(date.getDate() - 2);
  }
}
function dayOfWeekToString(day) {
  var DAYS = [
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
  ];
  return DAYS[day];
}
function dateToString(date) {
  return (
    dayOfWeekToString(date.getDay()) +
    ", " +
    (date.getMonth() + 1) +
    "/" +
    date.getDate()
  );
}

function updateMainSchedule() {
  var scheduleElement = document.getElementById("mainschedule");
  renderDate(globalDate);
  renderSchedule(globalDate, userSchedule, "full", scheduleElement, lunches);
  renderGitHubCommits();
}
function renderToast(text) {
  toast = document.getElementById("toast");
  console.log("Displaying toast");
  console.log(toast);
  toast.setAttribute("text", text);
  toast.show();
}
function getGpsSuccess(position, roomObj) {
  var radius = 6371000; // Radius of the earth
  var phi1 = position.coords.latitude * (Math.PI / 180);
  var phi2 = roomObj.latitude * (Math.PI / 180);
  var deltaPhi =
    (roomObj.latitude - position.coords.latitude) * (Math.PI / 180);
  var deltaLambda =
    (roomObj.longitude - position.coords.longitude) * (Math.PI / 180);
  var a =
    Math.sin(deltaPhi / 2) * Math.sin(deltaPhi / 2) +
    Math.cos(phi1) *
      Math.cos(phi2) *
      Math.sin(deltaLambda / 2) *
      Math.sin(deltaLambda / 2);
  var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  var d = radius * c;
  if (d > 200) {
    console.log("Too far away from EPS");
    return;
  }
  map = document.getElementById("map");
  marker = document.createElement("google-map-marker");
  marker.latitude = position.coords.latitude;
  marker.longitude = position.coords.longitude;
  marker.draggable = false;
  marker.title = "Your face";
  map.appendChild(marker);
}
function isStandardClass(letter) {
  var standardPeriods = [
    "O",
    "A",
    "B",
    "C",
    "D",
    "E",
    "F",
    "G",
    "H",
    "Advisory",
  ];
  return standardPeriods.indexOf(letter) >= 0;
}
function getGpsFail(error) {
  switch (error.code) {
    case error.PERMISSION_DENIED:
      console.log("User did not allow access to GPS");
      break;
    case error.POSITION_UNAVAILABLE:
      console.log("EPSchedule was not able to get location information");
      break;
    case error.TIMEOUT:
      console.log("Request to enable GPS timed out");
      break;
    case error.UNKNOWN_ERROR:
      console.log("Geolocation failed, error unknown");
      break;
  }
}
function requestAdditionalData(name, type, funct) {
  name = cleanString(name);
  var url = type + "/" + name;
  console.log("Requesting " + url);
  xhr = new XMLHttpRequest();
  xhr.onreadystatechange = function () {
    if (xhr.readyState == 4 && xhr.status == 200) {
      result = JSON.parse(xhr.responseText);
      funct(result);
    }
  };
  xhr.open("GET", url, true);
  xhr.send();
}
function renderRoom(roomObj) {
  
  var popup = document.getElementById("popup");
  var container = document.getElementById("popupContainer");
  console.log("Latitude = " + roomObj.latitude);
  console.log("Longitude = " + roomObj.longitude);
  container.innerHTML =
    '<google-map latitude="47.643455" longitude="-122.198935" id="map" zoom="18" disable-default-ui fit-to-markers>' +
    "</google-map>";
  
}
function renderBio(teacherBio) {
  var html = "";
  for (var i = 0; i < teacherBio.length; ++i) {
    html += "<p>" + teacherBio[i] + "</p>";
  }
  return html;
}
function renderTeacher(teacherObj) {
  var popupContainer = document.getElementById("popupContainer");
  var imgSrc = "teacher_photos_fullsize/" + teacherObj.firstname + "_";
  imgSrc = imgSrc + teacherObj.lastname + ".jpg";
  imgSrc = imgSrc.toLowerCase();
  var email = teacherObj.email;
  var innerHTMLStyle;
  var style = getComputedStyle(document.body);
  var bgColor = style.getPropertyValue("--background");
  innerHTMLStyle = "style='background-color: " + bgColor.toString() + "'";

  popupContainer.innerHTML =
    '<div class="teacher" layout vertical>' +
    '<paper-material class="header" elevation="2" ' +
    innerHTMLStyle +
    ">" +
    "<div layout horizontal center>" +
    '<img src="' +
    imgSrc +
    '" width="128px" height="128px">' +
    "<div layout vertical>" +
    '<p><a href="mailto:' +
    email +
    '""><iron-icon icon="communication:email"></iron-icon>' +
    '<span class="email">Email teacher</span></a></p>' +
    renderBio(teacherObj.bio) +
    "</div></div></paper-material>" +
    '<schedule-lite id="teacherschedule"></schedule-lite>' +
    "</div>";
  setTimeout(function () {
    finishLiteSchedule(document.getElementById("teacherschedule"), teacherObj);
  }, 0);
}
function stringifyRooms(arr) {
  tempString = "";
  for (var i = 0; i < arr.length; i++) {
    tempString += arr[i];

    if (i != arr.length - 1) {
      tempString += ", ";
    }
  }
  return tempString;
}
function renderPeriod(periodObj) {
  var popupContainer = document.getElementById("popupContainer");

  var style = getComputedStyle(document.body);
  var bgColor = style.getPropertyValue("--background");
  var innerHTMLStyle = "style='background-color: " + bgColor.toString() + "'";
  popupContainer.innerHTML =
    '<div class="period" layout vertical>' +
    '<div class="halfwidth periodbottomspace"><paper-material class="periodsubcontainer" ' +
    innerHTMLStyle +
    ' elevation="2">' +
    '<div class="periodheading" ' +
    innerHTMLStyle +
    ">Other classes to take:</div>" +
    '<x-schedule id="altclassesschedule" show="all" swipe-disabled></x-schedule>' +
    "</paper-material></div>" +
    '<div class="halfwidth"><div class="periodbottomspace" ' +
    innerHTMLStyle +
    '><paper-material class="periodsubcontainer periodmediumpadding"  ' +
    innerHTMLStyle +
    ' elevation="2">' +
    '<div class="periodheading" ' +
    innerHTMLStyle +
    ">Empty rooms:</div>" +
    '<div class="freeroomswarning" ' +
    innerHTMLStyle +
    ">These are the classrooms without a class taking place this period." +
    "You may use them to work or study as you choose. Note that there may be other students or teachers already in these rooms.</div>" +
    "<div " +
    innerHTMLStyle +
    ">" +
    stringifyRooms(periodObj["freerooms"]) +
    "</div>" +
    "</paper-material></div>" +
    '<div class="periodbottomspace"><paper-material class="periodsubcontainer" elevation="2">' +
    '<div class="periodheading"' +
    innerHTMLStyle +
    ">Current class:</div>" +
    '<x-schedule id="currentperiodclassschedule" show="all" swipe-disabled></x-schedule>' +
    "</paper-material></div></div>" +
    "</div>";

  setTimeout(function () {
    var e = document.getElementById("altclassesschedule");
    var f = document.getElementById("currentperiodclassschedule");

    renderSchedule(copyDate(globalDate), periodObj, "core", e, {}, false);
    console.log({ classes: [[periodObj["currentclass"]] * 3] });

    renderSchedule(
      copyDate(globalDate),
      {
        classes: [
          [periodObj["currentclass"]],
          [periodObj["currentclass"]],
          [periodObj["currentclass"]],
        ],
      },
      "core",
      f,
      {},
      false,
    );

    e.behaviors = [];
    f.behaviors = [];
  }, 20);
}
function renderStudent(studentObj) {
  var popupContainer = document.getElementById("popupContainer");
  var email = studentObj.email;
  email = email.toLowerCase();
  if (studentObj.grade) {
    var grade = studentObj.grade + "th Grade";
    var name = studentObj.preferred_name
      ? studentObj.preferred_name
      : studentObj.firstname;
    var officeTag = "";
    var advisoryTag =
      '<p><iron-icon icon="icons:perm-identity"></iron-icon>' +
      "Advisor: " +
      studentObj.advisor.charAt(1).toUpperCase() +
      studentObj.advisor.slice(2) +
      "</p>";
  } else {
    var grade = "";
    var name = studentObj.preferred_name
      ? studentObj.preferred_name
      : studentObj.firstname;
    name += " " + studentObj.lastname;
    var officeTag =
      '<p><iron-icon icon="icons:home"></iron-icon>' +
      "Office: " +
      studentObj.office +
      "</p>";
    var advisoryTag = "";
  }
  var innerHTMLStyle;
  var style = getComputedStyle(document.body);
  var bgColor = style.getPropertyValue("--background");
  innerHTMLStyle = "style='background-color: " + bgColor.toString() + "'";
  popupContainer.innerHTML =
    '<div class="teacher" layout vertical>' +
    '<paper-material class="header" elevation="2" ' +
    innerHTMLStyle +
    ">" +
    "<div layout horizontal center>" +
    (studentObj.username === "cwest" ? '<a href="https://connorwe.st">' : "") +
    '<img src="' +
    studentObj.photo_url +
    "?t=" +
    Date.now() +
    '" width="360px"' +
    "\" onerror=\"if (this.src != '/static/images/placeholder.png') this.src = '/static/images/placeholder.png';\">" +
    (document.getElementById("namefjs").innerText === "cwest" ? "</a>" : "") +
    "<div layout vertical><h3>" +
    ((document.getElementById("namefjs").innerText === studentObj.username) &
    !document.getElementById("sharephototoggle").checked
      ? "<span class='leftfloat padleft' style='font-size:12px; !important;font-weight: normal !important;'>You have photo sharing turned off, so others cannot see your photo</span><br>"
      : "") +
    '<span class="grade">' +
    grade +
    "</span></h3>" +
    '<p><a href="mailto:' +
    email +
    '""><iron-icon icon="communication:email"></iron-icon>' +
    '<span class="email">Email ' +
    name +
    "</span></a></p>" +
    officeTag +
    advisoryTag +
    "</div></div></paper-material>" +
    '<schedule-lite id="studentschedule"></schedule-lite>' +
    "</div>";
  setTimeout(function () {
    finishLiteSchedule(document.getElementById("studentschedule"), studentObj);
  }, 0);
}
function finishLiteSchedule(scheduleElement, otherUserObj) {
  scheduleElement.date = copyDate(globalDate);
  scheduleElement.addEventListener("swiped", function (e) {
    adjustDate(scheduleElement.date, e.detail.direction == "left" ? 1 : -1);
    updateLiteSchedule(scheduleElement, otherUserObj);
  });
  updateLiteSchedule(scheduleElement, otherUserObj);
}
function updateLiteSchedule(scheduleElement, otherUserObj) {
  scheduleElement.dateString = dateToString(scheduleElement.date);
  renderSchedule(scheduleElement.date, otherUserObj, "lite", scheduleElement);
}
function renderDate(dateObj) {
  var daySpan = document.getElementById("day");
  daySpan.firstChild.textContent = dateToString(dateObj);
}

function getSchool(grade) {
  if (grade <= 8) {
    return "MS";
  } else {
    return "US";
  }
}

function getTermId(dateObj) {
  for (var termId = 0; termId < 2; termId++) {
    if (dateObj < triStartDates[termId + 1]) break;
  }
  console.log("Converted " + dateObj + " to a term ID of " + termId);
  return termId;
}

function toTwoDig(num) {
  var s = num.toString();
  if (s.length == 1) {
    return "0" + s;
  } else {
    return s;
  }
}
function makeDateKey(dateObj) {
  var datekey =
    dateObj.getFullYear() +
    "-" +
    toTwoDig(dateObj.getMonth() + 1) +
    "-" +
    toTwoDig(dateObj.getDate());
  return datekey;
}
function getScheduleTypeForDate(dateObj, exceptions) {
  var datekey = makeDateKey(dateObj);
  var day = exceptions[0][datekey];
  return exceptions[1][day];
}

function incorrectSchool(s, school) {
  var other = "MS";
  if (school == "MS") {
    other = "US";
  }

  if (~s.indexOf(other)) {
    return true;
  }
  if (school == "MS" && ~s.indexOf("Seminars")) {
    return true;
  }
  return false;
}

function createClassEntry(schedule, school, day, currentSlot, type, lunchInfo) {
  var scheduleObj;
  var foundClass = false;

  if (incorrectSchool(day[currentSlot]["period"], school)) {
    return null;
  } else {
    var period = day[currentSlot]["period"].replace(" - " + school, "");
  }
  if (isStandardClass(period)) {
    for (var k = 0; k < schedule["classes"].length; k++) {
      var clazz = schedule["classes"][k];
      if (clazz["period"] == period) {
        if (clazz["teacher_username"]) {
          var tu = clazz["teacher_username"];
          var teacher = tu.charAt(1).toUpperCase() + tu.slice(2);
          scheduleObj = {
            name: clazz["name"],
            teacher: teacher,
            teacherUsername: clazz["teacher_username"],
            room: clazz["room"],
            period: period,
            time: "",
          };

          if (type == "core") {
            scheduleObj["studentCount"] = clazz["students"].toString();
          }
        } else {
          scheduleObj = {
            name: schedule["classes"][k]["name"],
            teacher: "",
            teacherUsername: "",
            room: "",
            period: period,
            time: "",
          };
        }
        foundClass = true;
        break;
      }
    }
    if (!foundClass) {
      return null;
    }
  } else {

    scheduleObj = {
      name: period,
      teacher: "",
      room: "",
      period: "X",
      time: "",
    };
    LPC_COMMONS_CLASSES = [
      "Assembly",
      "US Community",
      "Lunch (US)",
      "Lunch (MS)",
    ];
    if (LPC_COMMONS_CLASSES.includes(scheduleObj.name)) {
      scheduleObj.room = "LPC Commons";
    }
    if (scheduleObj.name == "Lunch (US)" || scheduleObj.name == "Lunch (MS)") {
      scheduleObj.lunchInfo = lunchInfo;
    }
  }
  if (scheduleObj.teacher == "N/A") {
    scheduleObj.teacher = "";
  }
  if (scheduleObj.room == "N/A") {
    scheduleObj.room = "";
  }
  if (type == "full" || type == "core") {
    addScheduleImages(scheduleObj, schedule, type);
  } else if (type == "lite") {
    if (isStandardClass(scheduleObj.period)) {
      scheduleObj.shared = isSharedClass(scheduleObj, schedule.termid);
    } else {
      return null; // Skip over lunch, assembly, etc.
    }
  }
  scheduleObj.termId = termId;
  if (type != "core") {
    var times = day[currentSlot]["times"].split("-");
    scheduleObj.startTime = times[0].trim();
    scheduleObj.endTime = times[1].trim();
  }
  return scheduleObj;
}

IMAGE_CDN = "https://epschedule-avatars.storage.googleapis.com/";

function isDarkMode() {
  return (
    window.matchMedia &&
    window.matchMedia("(prefers-color-scheme: dark)").matches
  );
}

function addScheduleImages(scheduleObj, userSchedule, type) {
  if (scheduleObj.teacher != "" || type == "core") {
    var sanitized_teacher_name;
    sanitized_teacher_name = scheduleObj.teacher.toLowerCase();
    sanitized_teacher_name = sanitized_teacher_name.replace(/ /g, "_");
    scheduleObj.avatar = IMAGE_CDN + scheduleObj.teacherUsername + ".jpg";
    scheduleObj.teacherLink = "/teacher/" + sanitized_teacher_name;

  } else if (scheduleObj.period == "X" || scheduleObj.name == "Free Period") {
    scheduleObj.teacherLink = "";
    var image_name = scheduleObj.name.toLowerCase();
    image_name = image_name.replace("/", "");
    image_name = image_name.replace(/\s/g, "");
    image_name = image_name.replace(/(\(.*?\))/g, ""); // Remove text between parentheses
    if (isDarkMode()) {
      scheduleObj.avatar = "/static/images/" + image_name + "_dark.svg";
    } else {
      scheduleObj.avatar = "/static/images/" + image_name + ".svg";
    }
  }
  scheduleObj.roomLink =
    "/room/" + scheduleObj.room.toLowerCase().replace(/ /g, "_");
}

function isSharedClass(scheduleObj, termid) {
  var userClasses = userSchedule.classes[termid];
  for (var i = 0; i < userClasses.length; i++) {
    if (
      userClasses[i].period == scheduleObj.period &&
      userClasses[i].name == scheduleObj.name &&
      (userClasses[i].teacher_username != null
        ? userClasses[i].teacher_username
        : "") == scheduleObj.teacherUsername
    ) {
      return true;
    }
  }
  return false;
}

function getLunchForDate(lunch_list, date) {
  for (var i = 0; i < lunch_list.length; i++) {
    var lunch = lunch_list[i];
    if (
      date.getDate() == lunch["day"] &&
      date.getMonth() + 1 == lunch["month"] &&
      date.getFullYear() == lunch["year"]
    ) {
      return lunch;
    }
  }
}

function dateIsCurrentDay(d1) {
  var d2 = new Date();
  return (
    d1.getDate() == d2.getDate() &&
    d1.getMonth() == d2.getMonth() &&
    d1.getYear() == d2.getYear()
  );
}

function renderSchedule(
  dateObj,
  schedule,
  type,
  scheduleElement,
  lunch_list,
  expandable = true,
) {
  termId = getTermId(dateObj);

  if ((type == "full" || type == "lite") && schedule.grade !== null) {
    var school = getSchool(schedule.grade);
  }

  var todaySchedule = [];

  if (type == "full") {
    var lunchInfo = getLunchForDate(lunch_list, dateObj);
  }

  var day = getScheduleTypeForDate(dateObj, days);
  if (type == "core") {
    day = [{ period: schedule["classes"][termId][0]["period"], times: "" }];
  }
  scheduleElement.type = type;
  scheduleElement.expandable = expandable;
  if (!day) {
    var imageObj = {
      url: "/static/images/epslogolarge.png",
      text: "No School",
    };
    scheduleElement.allDayEvent = imageObj;
    scheduleElement.entries = null; // Clear the classes
  } else if (type == "core") {
    for (
      var currentClass = 0;
      currentClass < schedule["classes"][termId].length;
      currentClass++
    ) {
      var scheduleObj = createClassEntry(
        { classes: [schedule["classes"][termId][currentClass]] },
        school,
        day,
        0,
        type,
        lunchInfo,
      );
      todaySchedule.push(scheduleObj);
    }
    if (schedule.early_dismissal && todaySchedule.length > 0) {
      var lastEntry = todaySchedule[todaySchedule.length - 1];
      var earlyDismissalTime = lastEntry.endTime;
      var earlyDismissalObj = {
        name: "Early Dismissal",
        teacher: "",
        teacherUsername: "",
        room: "",
        period: "ED",
        time: "",
        startTime: earlyDismissalTime,
        endTime: earlyDismissalTime,
        avatar: isDarkMode()
          ? "/static/images/earlydismissal_dark.svg"
          : "/static/images/earlydismissal.svg",
        teacherLink: "",
        roomLink: "",
        termId: termId,
      };
      todaySchedule.push(earlyDismissalObj);
    }
    scheduleElement.entries = todaySchedule;
    scheduleElement.allDayEvent = null;
  } else if (day.length > 1) {
    for (var currentSlot = 0; currentSlot < day.length; currentSlot++) {
      var triSchedule = JSON.parse(JSON.stringify(schedule));
      triSchedule["classes"] = triSchedule["classes"][termId];
      triSchedule["termid"] = termId;
      var scheduleObj = createClassEntry(
        triSchedule,
        school,
        day,
        currentSlot,
        type,
        lunchInfo,
      );
      if (scheduleObj) {
        todaySchedule.push(scheduleObj);
      }
    }
    if (schedule.early_dismissal && todaySchedule.length > 0) {
      var lastEntry = todaySchedule[todaySchedule.length - 1];
      var earlyDismissalTime = lastEntry.endTime;
      var earlyDismissalObj = {
        name: "Early Dismissal",
        teacher: "",
        teacherUsername: "",
        room: "",
        period: "ED",
        time: "",
        startTime: earlyDismissalTime,
        endTime: earlyDismissalTime, // Same time, just a marker
        avatar: isDarkMode()
          ? "/static/images/earlydismissal_dark.svg"
          : "/static/images/earlydismissal.svg",
        teacherLink: "",
        roomLink: "",
        termId: termId,
      };
      todaySchedule.push(earlyDismissalObj);
    }
    scheduleElement.entries = todaySchedule;
    scheduleElement.allDayEvent = null;
    scheduleElement.isOnCampus = true;
  } else if (day.length == 1) {
    var imageObj = {
      url: "/static/images/epslogolarge.png",
      text: day[0]["period"],
    };
    scheduleElement.allDayEvent = imageObj;
    scheduleElement.entries = null; // Clear the classes
  }
  if (type == "full" || type == "core") {
    scheduleElement.onTeacherTap = function (e) {
      var username = e.model.item.teacherUsername;
      requestAdditionalData(username, "student", renderStudent);
      openPopup(e.model.item.teacher);
    };
    scheduleElement.onStudentTap = function (e) {
      var orig_name = e.model.item.firstname + " " + e.model.item.lastname;
      var username = e.model.item.email.slice(0, -17);
      requestAdditionalData(username, "student", renderStudent);
      openPopup(orig_name);
    };
    scheduleElement.onRoomTap = function (e) {
      var orig_name = e.model.item.room;
      var name = orig_name.replace("-", "_");
      requestAdditionalData(name, "room", renderRoom);
      openPopup(orig_name);
    };
    scheduleElement.onPeriodTap = function (e) {
      requestAdditionalData(e.model.item.period, "period", renderPeriod);
      openPopup(e.model.item.period + " Period");
    };
    scheduleElement.onRate = function (rating) {
      var data = new FormData();
      data.append("rating", rating);
      sendPostMessage("lunch", ratingSuccessful, data);
    };
    if (type == "core") {
      scheduleElement.behaviors = [];
    }

    scheduleElement.isToday = dateIsCurrentDay(dateObj);
  }
}
function ratingSuccessful(result) {
  renderToast(result.error);
}
function openSearchBar() {
  var titlebar = document.querySelector(".headerbarpages");
  titlebar.entryAnimation = "slide-from-top-animation";
  titlebar.exitAnimation = "";
  titlebar.selected = 1;
  var input = document.querySelector("paper-input.paper-typeahead-input");
  input.tabIndex = 1; // We can only focus elements with tab indexes, so we need to give our paper-input one

  setTimeout(function () {
    input.focus();
  }, 200);
}
function closeSearchBar() {
  var titlebar = document.querySelector(".headerbarpages");
  titlebar.exitAnimation = "slide-up-animation";
  titlebar.entryAnimation = "";
  titlebar.selected = 0;
}
function openPopup(title) {
  var titleSpan = document.getElementById("popupTitle");
  titleSpan.textContent = title;
  pages.entryAnimation = "slide-from-right-animation";
  pages.exitAnimation = "";
  pages.selected = 1;
}

function closePopup() {
  pages.entryAnimation = "";
  pages.exitAnimation = "slide-right-animation";
  pages.selected = 0;
}

function cleanString(text) {
  text = text.toLowerCase();
  text = text.replace(/ /g, "_"); // Remove spaces
  text = text.replace(/\./g, ""); // Remove periods
  return text;
}

function closePrivacyDialog() {
  document.getElementById("privacydialog").close();
  var share_photo = document.getElementById("initialsharephototoggle");
  sendUpdatePrivacyRequest(share_photo.checked);
}

function changePrivacySettings() {
  document.getElementById("privacydialogcollapse").show();
}

document.addEventListener("keydown", (event) => {
  var drawerState = document.querySelector("#drawerpanel").selected;
  if (drawerState == "drawer") {
    return;
  }

  var titlebar = document.querySelector(".headerbarpages");
  if (pages.selected == 0 && titlebar.selected == 0) {
    if (event.keyCode == 37) {
      dateBack();
    } else if (event.keyCode == 39) {
      dateForward();
    } else if (event.keyCode == 191) {
      openSearchBar();
    }
  } else if (titlebar.selected == 1) {
    if (event.keyCode == 27) {
      var typeAhead = document.querySelector("paper-typeahead-input");
      typeAhead.inputValue = "";
      closeSearchBar();
    }
  } else if (pages.selected == 1) {
    if (event.keyCode == 27) {
      closePopup();
    }
  }
});

document.addEventListener("WebComponentsReady", () => {
  var scheduleElement = document.getElementById("mainschedule");
  scheduleElement.addEventListener("swiped", scheduleSwiped, false);
  updateMainSchedule();
  var typeAhead = document.querySelector("paper-typeahead-input");
  typeAhead.addEventListener("pt-item-confirmed", () => {
    var obj = typeAhead.inputObject;
    requestAdditionalData(obj.username, "student", renderStudent);
    openPopup(obj.name);
    typeAhead.inputValue = "";
    closeSearchBar();
  });
  const drawer = document.getElementById("drawerpanel");
  if (drawer) {
    drawer.addEventListener("transitionend", () => {
      const active = document.activeElement;
      if (
        active &&
        active.classList &&
        active.classList.contains("side-panel-boxes")
      ) {
        active.blur();
      }
      setTimeout(() => {
        const a = document.activeElement;
        if (a && a.classList && a.classList.contains("side-panel-boxes"))
          a.blur();
      }, 50);
    });
  }
});
