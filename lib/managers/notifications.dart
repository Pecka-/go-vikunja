// https://medium.com/@fuzzymemory/adding-scheduled-notifications-in-your-flutter-application-19be1f82ade8

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

import 'package:fluttertoast/fluttertoast.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as notifs;
import 'package:rxdart/subjects.dart' as rxSub;
import 'package:vikunja_app/api/client.dart';
import 'package:vikunja_app/api/task_implementation.dart';
import 'package:vikunja_app/service/services.dart';

import '../models/task.dart';

class NotificationClass {
  final int? id;
  final String? title;
  final String? body;
  final String? payload;
  late String currentTimeZone;
  notifs.NotificationAppLaunchDetails? notifLaunch;

  notifs.FlutterLocalNotificationsPlugin get notificationsPlugin =>
      new notifs.FlutterLocalNotificationsPlugin();

  static var androidSpecificsDueDate = notifs.AndroidNotificationDetails(
      "Vikunja1", "Due Date Notifications",
      channelDescription: "description",
      icon: 'vikunja_notification_logo',
      importance: notifs.Importance.high,
      actions: <notifs.AndroidNotificationAction>[
        notifs.AndroidNotificationAction("snooze", "Snooze", showsUserInterface: false, cancelNotification: true),
        notifs.AndroidNotificationAction("complete", "Complete", showsUserInterface: false, cancelNotification: true),
      ]);

  static var androidSpecificsReminders = notifs.AndroidNotificationDetails(
      "Vikunja2", "Reminder Notifications",
      channelDescription: "description",
      icon: 'vikunja_notification_logo',
      importance: notifs.Importance.high);

  late notifs.DarwinNotificationDetails iOSSpecifics;
  late notifs.NotificationDetails platformChannelSpecificsDueDate;
  late notifs.NotificationDetails platformChannelSpecificsReminders;

  NotificationClass({this.id, this.body, this.payload, this.title});

  final rxSub.BehaviorSubject<NotificationClass>
      didReceiveLocalNotificationSubject =
      rxSub.BehaviorSubject<NotificationClass>();
  final rxSub.BehaviorSubject<String> selectNotificationSubject =
      rxSub.BehaviorSubject<String>();

  Future<void> _initNotifications() async {
    var initializationSettingsAndroid =
        notifs.AndroidInitializationSettings('vikunja_logo');

    var initializationSettingsIOS = notifs.DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        // onDidReceiveLocalNotification:
        //     (int? id, String? title, String? body, String? payload) async {
        //   didReceiveLocalNotificationSubject.add(NotificationClass(
        //       id: id, title: title, body: body, payload: payload));
        // }
        );

    var initializationSettings = notifs.InitializationSettings(
        android: initializationSettingsAndroid, iOS: initializationSettingsIOS);
    await notificationsPlugin.initialize(initializationSettings,
        onDidReceiveNotificationResponse:
            (notifs.NotificationResponse resp) async {
      if (payload != null) {
        print('notification payload: ' + resp.payload!);
        selectNotificationSubject.add(resp.payload!);
      }
    }, onDidReceiveBackgroundNotificationResponse: backgroundNotificationResponse);
    print("Notifications initialised successfully");
  }
  
  @pragma('vm:entry-point')
  static void backgroundNotificationResponse(notifs.NotificationResponse response) async {
    if (response.id == null) {
      return;
    }

    tz.initializeTimeZones();
    
    final FlutterSecureStorage storage = new FlutterSecureStorage();
    var currentUser = await storage.read(key: 'currentUser');
    if (currentUser == null) {
      Fluttertoast.showToast(msg: "Failed to update task");
      return;
    }
    var token = await storage.read(key: currentUser);
    var urlBase = await storage.read(key: "${currentUser}_base");
    if (token == null) {
      Fluttertoast.showToast(msg: "Failed to update task");
      return;
    }

    var client = Client(null, token: token, base: urlBase, authenticated: true);
    var taskService = TaskAPIService(client);
    var notificationsPlugin = new notifs.FlutterLocalNotificationsPlugin();

    if (response.actionId == "snooze") {
      DateTime newDue = DateTime.now().add(Duration(hours: 2));
      await taskService.snooze(response.id ?? 0, newDue).then((success) async {
        if (!success) {
          Fluttertoast.showToast(msg: "Failed to snooze task");
        } else {
          var payloadMap = jsonDecode(response.payload!); // Deserialize the payload
          String title = payloadMap['title']; // Extract the title

          await scheduleNotification(
            "Due Reminder",
            "The task '" + title + "' is due.",
            notificationsPlugin,
            newDue,
            await FlutterTimezone.getLocalTimezone(),
            notifs.NotificationDetails(android: androidSpecificsDueDate, iOS: notifs.DarwinNotificationDetails()),
            id: response.id,
          );
        }
      });
      // });
    }
    else if (response.actionId == "complete") {
      // complete the task
      Task task = Task.fromJson(jsonDecode(response.payload!));
      await taskService.complete(task).then((success) {
        if (success) {
          Fluttertoast.showToast(msg: "Task completed");
        }
        else {
          Fluttertoast.showToast(msg: "Failed to complete task");
        }
      });
    }
  }

  static Future<void> showSnoozeOptions(BuildContext context, Function(DateTime) onSnoozeSelected) async {
    DateTime now = DateTime.now();
    DateTime oneHourLater = now.add(Duration(hours: 1));
    DateTime sixPmToday = DateTime(now.year, now.month, now.day, 18, 0);
    if (now.isAfter(sixPmToday)) {
      sixPmToday = sixPmToday.add(Duration(days: 1));
    }
    DateTime tomorrowEightAm = DateTime(now.year, now.month, now.day + 1, 8, 0);
    DateTime saturdayTenAm = now.add(Duration(days: (6 - now.weekday) % 7 + 1)).add(Duration(hours: 10));

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Snooze Options"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text("1 hour"),
                onTap: () => onSnoozeSelected(oneHourLater),
              ),
              ListTile(
                title: Text("6pm today"),
                onTap: () => onSnoozeSelected(sixPmToday),
              ),
              ListTile(
                title: Text("Tomorrow 8am"),
                onTap: () => onSnoozeSelected(tomorrowEightAm),
              ),
              ListTile(
                title: Text("Saturday 10am"),
                onTap: () => onSnoozeSelected(saturdayTenAm),
              ),
            ],
          ),
        );
      },
    );
  }  

  Future<void> notificationInitializer() async {
    iOSSpecifics = notifs.DarwinNotificationDetails();
    platformChannelSpecificsDueDate = notifs.NotificationDetails(
        android: androidSpecificsDueDate, iOS: iOSSpecifics);
    platformChannelSpecificsReminders = notifs.NotificationDetails(
        android: androidSpecificsReminders, iOS: iOSSpecifics);
    currentTimeZone = await FlutterTimezone.getLocalTimezone();
    notifLaunch = await notificationsPlugin.getNotificationAppLaunchDetails();
    await _initNotifications();
    requestIOSPermissions();
    return Future.value();
  }

  static Future<void> scheduleNotification(
      String title,
      String description,
      notifs.FlutterLocalNotificationsPlugin notifsPlugin,
      DateTime scheduledTime,
      String currentTimeZone,
      notifs.NotificationDetails platformChannelSpecifics,
      {int? id, String? payload}) async {
    if (id == null) id = Random().nextInt(1000000);
    // TODO: move to setup
    tz.TZDateTime time =
        tz.TZDateTime.from(scheduledTime, tz.getLocation(currentTimeZone));
    if (time.difference(tz.TZDateTime.now(tz.getLocation(currentTimeZone))) <
        Duration.zero) return;
    print("scheduled notification for time " + time.toString());
    await notifsPlugin.zonedSchedule(
        id, title, description, time, platformChannelSpecifics,
        payload: payload,
        androidScheduleMode: notifs.AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: notifs
            .UILocalNotificationDateInterpretation
            .wallClockTime); // This literally schedules the notification
  }

  void sendTestNotification() {
    notificationsPlugin.show(Random().nextInt(10000000), "Test Notification",
        "This is a test notification", platformChannelSpecificsReminders);
  }

  void requestIOSPermissions() {
    notificationsPlugin
        .resolvePlatformSpecificImplementation<
            notifs.IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  Future<void> scheduleDueNotifications(TaskService taskService, SettingsManager settingsManager, bool scheduleAll) async {
    List<Task>? tasks;

    DateTime newLastSync = DateTime.now().toUtc();
    if (scheduleAll) {
      // get all incomplete tasks that are due or are to be reminded in the future
      tasks = await taskService.getByFilterString(
          "done=false && (due_date > now || reminders > now)", {
        "filter_include_nulls": ["false"]
      });
    }
    else {
      // just get those modified since last time we checked (with buffer)
      DateTime lastSync = (await settingsManager.getLastNotificationSync()).add(Duration(minutes: -5));
      String formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(lastSync);
      tasks = await taskService.getByFilterString(
          "updated >= ${formattedDate}", {
        "filter_include_nulls": ["false"]
      });
    }

    if (tasks == null) {
      print("did not receive tasks on notification update");
      return;
    }

    List<notifs.PendingNotificationRequest> pendingNotifications = await notificationsPlugin.pendingNotificationRequests();
    List<notifs.ActiveNotification> activeNotifications = await notificationsPlugin.getActiveNotifications();

    for (final task in tasks) {
      if (task.done || task.dueDate == null || task.dueDate?.isAfter(DateTime.now()) == true) {
        //task is complete, has no due date or the due date is in the future, cancel any pending notification or displayed notification
        pendingNotifications.where((n) => n.id == task.id).forEach((n) => notificationsPlugin.cancel(task.id));
        activeNotifications.where((n) => n.id == task.id).forEach((n) => notificationsPlugin.cancel(task.id));
        // if it's complete or has no due date, we don't need to schedule a new notification; if it's in the future, we'll schedule it later
        if (task.done || task.dueDate == null)
        {
          continue;
        }
      }

      for (final reminder in task.reminderDates) {
        scheduleNotification(
          "Reminder",
          "This is your reminder for '" + task.title + "'",
          notificationsPlugin,
          reminder.reminder,
          await FlutterTimezone.getLocalTimezone(),
          platformChannelSpecificsReminders,
          id: (reminder.reminder.millisecondsSinceEpoch / 1000).floor(),
          payload: json.encode(task.toJSON()),
        );
      }
      if (task.hasDueDate) {
        scheduleNotification(
          "Due Reminder",
          "The task '" + task.title + "' is due.",
          notificationsPlugin,
          task.dueDate!,
          await FlutterTimezone.getLocalTimezone(),
          platformChannelSpecificsDueDate,
          id: task.id,
          payload: json.encode(task.toJSON()),
        );
        //print("scheduled notification for time " + task.dueDate!.toString());
      }
    }
    settingsManager.setLastNotificationSync(newLastSync);
    print("notifications scheduled successfully");
  }
}
