/**
 * McFly: mirror a Google calendar onto the display, from inside Google.
 *
 * For a calendar Google won't give a "Secret address in iCal format" for
 * (a work calendar whose admin turned external sharing off, or one shared
 * with you). This runs as you in Apps Script, so it reads whatever you can
 * see, and every 15 minutes pushes the next 60 days (and the past day) to
 * McFly's ingest API as one calendar, whole: moved and cancelled events
 * follow. It sends titles, times and locations only, never descriptions or
 * guests, and skips events you declined.
 *
 * Setup (docs/AGENTS.md, "A Google calendar without a secret address"):
 *   1. mcfly.bot → Agents → New agent ("ARMRA calendar"); copy its key.
 *   2. Google Calendar → Settings → the calendar → Integrate calendar:
 *      copy its Calendar ID.
 *   3. script.google.com, signed in as the account that sees the calendar
 *      → New project → paste this file.
 *   4. Project Settings → Script Properties: MCFLY_KEY = the key,
 *      CALENDAR_ID = the Calendar ID, and optionally CALENDAR_NAME (the
 *      name on the display; default: the calendar's own name).
 *   5. Pick `setup` in the toolbar → Run → allow access. It pushes once and
 *      schedules itself every 15 minutes. `stop` removes the schedule.
 *
 * The key lives only in Script Properties, never in this file.
 */

var MCFLY_INGEST = 'https://uxvzhlkvbrwjlwxylkdd.supabase.co/functions/v1/ingest/events';
var DAYS_AHEAD = 60;
var MAX_EVENTS = 1000; // the most one push may carry

function setup() {
  stop();
  ScriptApp.newTrigger('pushToMcFly').timeBased().everyMinutes(15).create();
  pushToMcFly();
}

function stop() {
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'pushToMcFly') ScriptApp.deleteTrigger(t);
  });
}

function pushToMcFly() {
  var props = PropertiesService.getScriptProperties();
  var key = props.getProperty('MCFLY_KEY');
  var calendarId = props.getProperty('CALENDAR_ID');
  if (!key) throw new Error('Add MCFLY_KEY in Project Settings → Script Properties (the agent key from mcfly.bot → Agents).');
  if (!calendarId) throw new Error('Add CALENDAR_ID in Project Settings → Script Properties (Google Calendar → Settings → the calendar → Integrate calendar).');
  var calendar = CalendarApp.getCalendarById(calendarId);
  if (!calendar) throw new Error('No calendar ' + calendarId + ' for this account: check CALENDAR_ID, and that this account can see it.');

  var body = mcflyPayload(calendar, props.getProperty('CALENDAR_NAME'), new Date());
  if (body.events.length === 0) {
    // McFly refuses an empty push; nothing is lost by waiting for the next one.
    console.log('No events in the next ' + DAYS_AHEAD + ' days; nothing pushed.');
    return;
  }
  var res = UrlFetchApp.fetch(MCFLY_INGEST, {
    method: 'post',
    contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + key },
    payload: JSON.stringify(body),
    muteHttpExceptions: true,
  });
  var code = res.getResponseCode();
  // A thrown error makes Apps Script email you when a scheduled run fails.
  if (code < 200 || code >= 300) throw new Error('McFly answered ' + code + ': ' + res.getContentText().slice(0, 300));
  console.log('Pushed ' + body.events.length + ' events to "' + body.calendar + '".');
}

// The request body for McFly's events feed (docs/AGENTS.md, "Events").
function mcflyPayload(calendar, name, now) {
  var zone = Session.getScriptTimeZone();
  var from = new Date(now.getTime() - 24 * 3600 * 1000);
  var to = new Date(now.getTime() + DAYS_AHEAD * 24 * 3600 * 1000);
  var color = /^#[0-9a-f]{6}$/i.test(calendar.getColor() || '') ? calendar.getColor() : null;
  var events = [];
  calendar.getEvents(from, to).forEach(function (e) {
    if (events.length >= MAX_EVENTS) return;
    if (e.getMyStatus() === CalendarApp.GuestStatus.NO) return; // declined
    var start = e.getStartTime();
    var event = {
      // Every instance of a repeating event shares its iCal id: add the start.
      id: (e.getId() + '@' + start.getTime()).slice(0, 200),
      title: (e.getTitle() || 'Busy').slice(0, 300),
    };
    if (e.isAllDayEvent()) {
      // Local midnight with this zone's offset, so the display (which places
      // events by local date) shows it on the right day. The end is the last
      // day's 23:59:59: Google's end date is the day after (never before the
      // start, should it ever come back inclusive).
      var first = e.getAllDayStartDate();
      var last = new Date(Math.max(first.getTime(), e.getAllDayEndDate().getTime() - 1000));
      event.starts_at = Utilities.formatDate(first, zone, "yyyy-MM-dd'T'00:00:00XXX");
      event.ends_at = Utilities.formatDate(last, zone, "yyyy-MM-dd'T'23:59:59XXX");
      event.all_day = true;
    } else {
      event.starts_at = start.toISOString();
      event.ends_at = e.getEndTime().toISOString();
    }
    var where = (e.getLocation() || '').trim();
    if (where) event.location = where.slice(0, 300);
    if (color) event.color = color;
    events.push(event);
  });
  return { calendar: (name || calendar.getName() || 'Google').slice(0, 80), replace: true, events: events };
}
