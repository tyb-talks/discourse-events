import { default as computed, observes } from 'ember-addons/ember-computed-decorators';
import { setupEvent, timezoneLabel } from '../lib/date-utilities';

const DATE_FORMAT = 'YYYY-MM-DD';
const TIME_FORMAT = 'HH:mm';
const TIMEZONES = moment.tz.names().reduce((names, n) => {
  if (n.indexOf('+') === -1) {
    const offset = moment.tz(n).format('Z');
    const name = timezoneLabel(n);
    names.push({
      id: n,
      name,
      offset
    });
  }

  return names;
}, []).sort((a, b) => {
  return parseInt(a.offset.replace(':', ''), 10) -
         parseInt(b.offset.replace(':', ''), 10);
});

export default Ember.Controller.extend({
  title: 'add_event.modal_title',
  endEnabled: false,
  allDay: false,
  timezones: TIMEZONES,
  showTimezone: false,

  setup() {
    const event = this.get('model.event');
    const { start, end, allDay } = setupEvent(event);
    let props = {};

    if (allDay) {
      let startDate = start.format(DATE_FORMAT);
      let endDate = end.format(DATE_FORMAT);
      let endEnabled = moment(endDate).isAfter(startDate, 'day');

      props = {
        allDay,
        startDate,
        endDate,
        endEnabled,
      };
    } else if (start) {
      let s = start || this.nextInterval();
      props['startDate'] = s.format(DATE_FORMAT);
      props['startTime'] = s.format(TIME_FORMAT);

      if (end) {
        let endDate = end.format(DATE_FORMAT);
        let endTime = end.format(TIME_FORMAT);
        props['endDate'] = endDate;
        props['endTime'] = endTime;
        props['endEnabled'] = true;
      }
    }

    if (start && event.timezone) {
      props['timezone'] = event.timezone;
    }

    this.setProperties(props);
    if (props['startTime']) this.setupTimePicker('start');
    if (props['endTime'])this.setupTimePicker('end');
  },

  setupTimePicker(type) {
    const time = this.get(`${type}Time`);
    Ember.run.scheduleOnce('afterRender', this, () => {
      const $timePicker = $(`#${type}-time-picker`);
      $timePicker.timepicker({ timeFormat: 'H:i' });
      $timePicker.timepicker('setTime', time);
      $timePicker.change(() => this.set(`${type}Time`, $timePicker.val()));
    });
  },

  @observes('endEnabled')
  setupOnEndEnabled() {
    const endEnabled = this.get('endEnabled');
    if (endEnabled) {
      const endDate = this.get('endDate');
      if (!endDate) {
        this.set('endDate', this.get('startDate'));
      }

      const allDay = this.get('allDay');
      if (!allDay) {
        const endTime = this.get('endTime');
        if (!endTime) {
          this.set('endTime', this.get('startTime'));
        }

        this.setupTimePicker('end');
      }
    }
  },

  @observes('allDay')
  setupOnAllDayRevert() {
    const allDay = this.get('allDay');
    if (!allDay) {
      const start = this.nextInterval();
      const startTime = start.format(TIME_FORMAT);
      this.set('startTime', startTime);
      this.setupTimePicker('start');

      const endEnabled = this.get('endEnabled');
      if (endEnabled) {
        const end = moment(start).add(1, 'hours');
        const endTime = end.format(TIME_FORMAT);
        this.set('endTime', endTime);
        this.setupTimePicker('end');
      }
    }
  },

  nextInterval() {
    const ROUNDING = 30 * 60 * 1000;
    return moment(Math.ceil((+moment()) / ROUNDING) * ROUNDING);
  },

  @computed('startDate', 'startTime', 'endDate', 'endTime', 'endEnabled', 'allDay')
  notReady(startDate, startTime, endDate, endTime, endEnabled, allDay) {
    const datesInvalid = endEnabled ? moment(startDate).isAfter(moment(endDate)) : false;
    if (allDay) return datesInvalid;

    const timesValid = endEnabled ? moment(startTime, 'HH:mm').isAfter(moment(endTime, 'HH:mm')) : false;
    return datesInvalid || timesValid;
  },

  @computed('timezone')
  timezoneLabel(timezone) {
    const text = I18n.t('add_event.timezone');
    return timezone ? `${text}: ${timezoneLabel(timezone)}` : text;
  },

  resetProperties() {
    this.setProperties({
      startDate: null,
      startTime: null,
      endDate: null,
      endTime: null,
      endEnabled: false,
      allDay: false
    });
  },

  actions: {
    clear() {
      this.resetProperties();
      this.get('model.update')(null);
    },

    toggleShowTimezone() {
      this.toggleProperty('showTimezone');
    },

    clearTimezone() {
      this.set("timezone", null);
      this.toggleProperty('showTimezone');
    },

    addEvent() {
      const startDate = this.get('startDate');
      let event = null;

      if (startDate) {
        const timezone = this.get('timezone');
        let start = moment().tz(timezone);

        const allDay = this.get('allDay');
        const sMonth = moment(startDate).month();
        const sDate = moment(startDate).date();
        const startTime = this.get('startTime');
        let sHour = allDay ? 0 : moment(startTime, 'HH:mm').hour();
        let sMin = allDay ? 0 : moment(startTime, 'HH:mm').minute();

        event = {
          timezone,
          all_day: allDay,
          start: start.month(sMonth).date(sDate).hour(sHour).minute(sMin).toISOString()
        };

        const endEnabled = this.get('endEnabled');
        if (endEnabled) {
          let end = moment().tz(timezone);
          const endDate = this.get('endDate');
          const eMonth = moment(endDate).month();
          const eDate = moment(endDate).date();
          const endTime = this.get('endTime');
          let eHour = allDay ? 0 : moment(endTime, 'HH:mm').hour();
          let eMin = allDay ? 0 : moment(endTime, 'HH:mm').minute();

          event['end'] = end.month(eMonth).date(eDate).hour(eHour).minute(eMin).toISOString();
        }
      }

      this.get('model.update')(event);
      this.resetProperties();
      this.send("closeModal");
    }
  }
});
