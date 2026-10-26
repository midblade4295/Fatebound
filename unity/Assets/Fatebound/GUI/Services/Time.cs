// Fatebound engine services (Unity port): Godot's Time singleton (core/os/time.cpp) -- monotonic ticks since start, the
// Unix clock, and the calendar conversions with Godot's exact arithmetic (proleptic Gregorian, any year, negative
// times, its dictionary keys and string formats). "from_system" reads the device clock (local time with dst, or UTC).
using System;
using System.Diagnostics;
using Fatebound.Sim;

namespace Fatebound.GUI
{
    public static class Time
    {
        public const int MONTH_JANUARY = 1, MONTH_FEBRUARY = 2, MONTH_MARCH = 3, MONTH_APRIL = 4, MONTH_MAY = 5, MONTH_JUNE = 6,
            MONTH_JULY = 7, MONTH_AUGUST = 8, MONTH_SEPTEMBER = 9, MONTH_OCTOBER = 10, MONTH_NOVEMBER = 11, MONTH_DECEMBER = 12;
        public const int WEEKDAY_SUNDAY = 0, WEEKDAY_MONDAY = 1, WEEKDAY_TUESDAY = 2, WEEKDAY_WEDNESDAY = 3, WEEKDAY_THURSDAY = 4,
            WEEKDAY_FRIDAY = 5, WEEKDAY_SATURDAY = 6;

        const long SECONDS_PER_DAY = 86400;
        const long UNIX_EPOCH_YEAR = 1970;
        static readonly Stopwatch Clock = Stopwatch.StartNew();
        static readonly long EpochTicks = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).Ticks;
        static readonly byte[][] MonthDays = {
            new byte[] { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 },
            new byte[] { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 } };

        // ------------------------------------------------------------------ clocks
        /// <summary>Milliseconds since the app started (monotonic).</summary>
        public static long GetTicksMsec() => GetTicksUsec() / 1000;

        /// <summary>Microseconds since the app started (monotonic).</summary>
        public static long GetTicksUsec()
        {
            long t = Clock.ElapsedTicks, f = Stopwatch.Frequency;
            return t / f * 1000000 + t % f * 1000000 / f;
        }

        /// <summary>Seconds since 1970-01-01 UTC, with the fraction.</summary>
        public static double GetUnixTimeFromSystem() => (DateTime.UtcNow.Ticks - EpochTicks) / 1e7;

        // ------------------------------------------------------------------ Godot's calendar arithmetic
        static bool IsLeap(long y) => y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);

        static long TotalLeapDays(long y)
        {
            if (y > 0)
            {
                --y;
                return 1 + (y / 4 - y / 100 + y / 400);
            }
            return y / 4 - y / 100 + y / 400;
        }

        static long YearToDays(long y) => y * 365 + TotalLeapDays(y);

        static long DaysToYear(long days)
        {
            long year = 400 * days / YearToDays(400);
            if (year < 0) --year;
            if (YearToDays(year) > days) --year;
            if (YearToDays(year + 1) <= days) ++year;
            return year;
        }

        static long PosMod(long a, long b)
        {
            long v = a % b;
            if ((v < 0 && b > 0) || (v > 0 && b < 0)) v += b;
            return v;
        }

        static void Hms(long t, out int hour, out int minute, out int second)
        {
            uint dayClock = (uint)PosMod(t, SECONDS_PER_DAY);
            second = (int)(dayClock % 60);
            dayClock /= 60;
            minute = (int)(dayClock % 60);
            hour = (int)(dayClock / 60);
        }

        static void Ymd(long t, out long year, out int month, out int day, out long dayNumber)
        {
            dayNumber = (long)Math.Floor(t / (double)SECONDS_PER_DAY);
            long d = dayNumber + YearToDays(UNIX_EPOCH_YEAR);
            year = DaysToYear(d);
            d -= YearToDays(year);
            int m = 0;
            var table = MonthDays[IsLeap(year) ? 1 : 0];
            while (d >= table[m])
            {
                d -= table[m];
                m++;
            }
            month = m + 1;
            day = (int)d + 1;
        }

        static long Weekday(long dayNumber) => PosMod(dayNumber + WEEKDAY_THURSDAY, 7);

        // ------------------------------------------------------------------ from a Unix time
        public static GDict GetDatetimeDictFromUnixTime(long t)
        {
            Hms(t, out int hour, out int minute, out int second);
            Ymd(t, out long year, out int month, out int day, out long dn);
            return new GDict { { "year", year }, { "month", month }, { "day", day }, { "weekday", Weekday(dn) },
                { "hour", hour }, { "minute", minute }, { "second", second } };
        }

        public static GDict GetDatetimeDictFromUnixTime(double t) => GetDatetimeDictFromUnixTime(GD.Long(t));

        public static GDict GetDateDictFromUnixTime(long t)
        {
            Ymd(t, out long year, out int month, out int day, out long dn);
            return new GDict { { "year", year }, { "month", month }, { "day", day }, { "weekday", Weekday(dn) } };
        }

        public static GDict GetDateDictFromUnixTime(double t) => GetDateDictFromUnixTime(GD.Long(t));

        public static GDict GetTimeDictFromUnixTime(long t)
        {
            Hms(t, out int hour, out int minute, out int second);
            return new GDict { { "hour", hour }, { "minute", minute }, { "second", second } };
        }

        public static GDict GetTimeDictFromUnixTime(double t) => GetTimeDictFromUnixTime(GD.Long(t));

        static string DateTimeString(long year, int month, int day, int hour, int minute, int second, bool useSpace) =>
            GD.Fmt(useSpace ? "%04d-%02d-%02d %02d:%02d:%02d" : "%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hour, minute, second);

        public static string GetDatetimeStringFromUnixTime(long t, bool useSpace = false)
        {
            Hms(t, out int hour, out int minute, out int second);
            Ymd(t, out long year, out int month, out int day, out _);
            return DateTimeString(year, month, day, hour, minute, second, useSpace);
        }

        public static string GetDatetimeStringFromUnixTime(double t, bool useSpace = false) => GetDatetimeStringFromUnixTime(GD.Long(t), useSpace);

        public static string GetDateStringFromUnixTime(long t)
        {
            Ymd(t, out long year, out int month, out int day, out _);
            return GD.Fmt("%04d-%02d-%02d", year, month, day);
        }

        public static string GetDateStringFromUnixTime(double t) => GetDateStringFromUnixTime(GD.Long(t));

        public static string GetTimeStringFromUnixTime(long t)
        {
            Hms(t, out int hour, out int minute, out int second);
            return GD.Fmt("%02d:%02d:%02d", hour, minute, second);
        }

        public static string GetTimeStringFromUnixTime(double t) => GetTimeStringFromUnixTime(GD.Long(t));

        // ------------------------------------------------------------------ dictionaries and ISO 8601 strings
        static bool Validate(long year, long month, long day, long hour, long minute, long second)
        {
            string err = null;
            if (month == 0) err = "Invalid month value of: " + month + ", months are 1-indexed and cannot be 0. See the Time.Month enum for valid values.";
            else if (month < 0) err = "Invalid month value of: " + month + ".";
            else if (month > 12) err = "Invalid month value of: " + month + ". See the Time.Month enum for valid values.";
            else if (hour > 23 || hour < 0) err = "Invalid hour value of: " + hour + ".";
            else if (minute > 59 || minute < 0) err = "Invalid minute value of: " + minute + ".";
            else if (second > 59) err = "Invalid second value of: " + second + " (leap seconds are not supported).";
            else if (second < 0) err = "Invalid second value of: " + second + ".";
            else if (day == 0) err = "Invalid day value of: " + day + ", days are 1-indexed and cannot be 0.";
            else if (day < 0) err = "Invalid day value of: " + day + ".";
            else
            {
                int dim = MonthDays[IsLeap(year) ? 1 : 0][month - 1];
                if (day > dim) err = "Invalid day value of: " + day + " which is larger than the maximum for this month, " + dim + ".";
            }
            if (err != null) GD.PushError(err);
            return err == null;
        }

        static long DayNumber(long year, long month, long day)
        {
            long dn = day - 1;
            var table = MonthDays[IsLeap(year) ? 1 : 0];
            for (int i = 0; i < month - 1; i++) dn += table[i];
            dn += YearToDays(year);
            dn -= YearToDays(UNIX_EPOCH_YEAR);
            return dn;
        }

        static void FromDict(GDict d, out long year, out long month, out long day, out long hour, out long minute, out long second)
        {
            year = d.Has("year") ? d["year"].AsLong() : UNIX_EPOCH_YEAR;
            month = d.Has("month") ? d["month"].AsInt() : 1;
            day = d.Has("day") ? d["day"].AsInt() : 1;
            hour = d.Has("hour") ? d["hour"].AsInt() : 0;
            minute = d.Has("minute") ? d["minute"].AsInt() : 0;
            second = d.Has("second") ? d["second"].AsInt() : 0;
        }

        static int[] SplitInts(string s, char delim)
        {
            var parts = s.Split(delim);
            var r = new System.Collections.Generic.List<int>();
            foreach (var p in parts)
            {
                if (p.Length == 0) continue;
                r.Add(unchecked((int)ToInt(p)));
            }
            return r.ToArray();
        }

        static long ToInt(string s)
        {
            long integer = 0, sign = 1;
            int i = 0;
            if (i < s.Length && s[i] == '-') { sign = -1; i++; }
            else if (i < s.Length && s[i] == '+') i++;
            for (; i < s.Length && s[i] >= '0' && s[i] <= '9'; i++) integer = unchecked(integer * 10 + (s[i] - '0'));
            return sign * integer;
        }

        static bool ParseIso(string s, out long year, out long month, out long day, out long hour, out long minute, out long second)
        {
            year = UNIX_EPOCH_YEAR; month = 1; day = 1; hour = 0; minute = 0; second = 0;
            bool hasDate = false, hasTime = false;
            string date = "", time = "";
            if (s.IndexOf('T') > 0)
            {
                hasDate = hasTime = true;
                var a = s.Split('T');
                if (a.Length < 2) { GD.PushError("Invalid ISO 8601 date/time string."); return false; }
                date = a[0]; time = a[1];
            }
            else if (s.IndexOf(' ') > 0)
            {
                hasDate = hasTime = true;
                var a = s.Split(' ');
                if (a.Length < 2) { GD.PushError("Invalid ISO 8601 date/time string."); return false; }
                date = a[0]; time = a[1];
            }
            else if (s.Length > 1 && s.IndexOf('-', 1) > 0)
            {
                hasDate = true;
                date = s;
            }
            else if (s.IndexOf(':') > 0)
            {
                hasTime = true;
                time = s;
            }
            if (hasDate)
            {
                var a = SplitInts(date, '-');
                if (a.Length < 3) { GD.PushError("Invalid ISO 8601 date string."); return false; }
                year = a[0]; month = a[1]; day = a[2];
                if (s.IndexOf('-') == 0) year *= -1;
            }
            if (hasTime)
            {
                var a = SplitInts(time, ':');
                if (a.Length < 3) { GD.PushError("Invalid ISO 8601 time string."); return false; }
                hour = a[0]; minute = a[1]; second = a[2];
            }
            return true;
        }

        public static GDict GetDatetimeDictFromDatetimeString(string datetime, bool weekday)
        {
            if (!ParseIso(datetime, out long year, out long month, out long day, out long hour, out long minute, out long second)) return new GDict();
            var d = new GDict { { "year", year }, { "month", (int)(byte)month }, { "day", (int)day } };
            if (weekday) d["weekday"] = Weekday(DayNumber(year, month, day));
            d["hour"] = (int)hour;
            d["minute"] = (int)minute;
            d["second"] = (int)second;
            return d;
        }

        public static string GetDatetimeStringFromDatetimeDict(GDict datetime, bool useSpace)
        {
            if (datetime == null || datetime.IsEmpty()) { GD.PushError("Invalid datetime Dictionary: Dictionary is empty."); return ""; }
            FromDict(datetime, out long year, out long month, out long day, out long hour, out long minute, out long second);
            if (!Validate(year, month, day, hour, minute, second)) return "";
            return DateTimeString(year, (int)month, (int)day, (int)hour, (int)minute, (int)second, useSpace);
        }

        public static long GetUnixTimeFromDatetimeDict(GDict datetime)
        {
            if (datetime == null || datetime.IsEmpty()) { GD.PushError("Invalid datetime Dictionary: Dictionary is empty"); return 0; }
            FromDict(datetime, out long year, out long month, out long day, out long hour, out long minute, out long second);
            if (!Validate(year, month, day, hour, minute, second)) return 0;
            return DayNumber(year, month, day) * SECONDS_PER_DAY + hour * 3600 + minute * 60 + second;
        }

        public static long GetUnixTimeFromDatetimeString(string datetime)
        {
            if (!ParseIso(datetime, out long year, out long month, out long day, out long hour, out long minute, out long second)) return -1;
            if (!Validate(year, month, day, hour, minute, second)) return 0;
            return DayNumber(year, month, day) * SECONDS_PER_DAY + hour * 3600 + minute * 60 + second;
        }

        public static string GetOffsetStringFromOffsetMinutes(long offsetMinutes)
        {
            string sign = "+";
            if (offsetMinutes < 0) { sign = "-"; offsetMinutes = -offsetMinutes; }
            return GD.Fmt("%s%02d:%02d", sign, offsetMinutes / 60, offsetMinutes % 60);
        }

        // ------------------------------------------------------------------ the device clock
        static DateTime Now(bool utc, out bool dst)
        {
            var n = DateTime.UtcNow;
            if (utc) { dst = false; return n; }
            var local = n.ToLocalTime();
            dst = TimeZoneInfo.Local.IsDaylightSavingTime(local);
            return local;
        }

        public static GDict GetDatetimeDictFromSystem(bool utc = false)
        {
            var t = Now(utc, out bool dst);
            return new GDict { { "year", t.Year }, { "month", t.Month }, { "day", t.Day }, { "weekday", (int)t.DayOfWeek },
                { "hour", t.Hour }, { "minute", t.Minute }, { "second", t.Second }, { "dst", dst } };
        }

        public static GDict GetDateDictFromSystem(bool utc = false)
        {
            var t = Now(utc, out _);
            return new GDict { { "year", t.Year }, { "month", t.Month }, { "day", t.Day }, { "weekday", (int)t.DayOfWeek } };
        }

        public static GDict GetTimeDictFromSystem(bool utc = false)
        {
            var t = Now(utc, out _);
            return new GDict { { "hour", t.Hour }, { "minute", t.Minute }, { "second", t.Second } };
        }

        public static string GetDatetimeStringFromSystem(bool utc = false, bool useSpace = false)
        {
            var t = Now(utc, out _);
            return DateTimeString(t.Year, t.Month, t.Day, t.Hour, t.Minute, t.Second, useSpace);
        }

        public static string GetDateStringFromSystem(bool utc = false)
        {
            var t = Now(utc, out _);
            return GD.Fmt("%04d-%02d-%02d", t.Year, t.Month, t.Day);
        }

        public static string GetTimeStringFromSystem(bool utc = false)
        {
            var t = Now(utc, out _);
            return GD.Fmt("%02d:%02d:%02d", t.Hour, t.Minute, t.Second);
        }

        /// <summary>{"bias": minutes east of UTC now, "name": the zone's name}.</summary>
        public static GDict GetTimeZoneFromSystem()
        {
            var now = DateTime.UtcNow;
            var tz = TimeZoneInfo.Local;
            var local = now.ToLocalTime();
            return new GDict { { "bias", (long)tz.GetUtcOffset(now).TotalMinutes }, { "name", tz.IsDaylightSavingTime(local) ? tz.DaylightName : tz.StandardName } };
        }
    }
}
