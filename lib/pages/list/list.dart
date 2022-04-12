import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:vikunja_app/components/AddDialog.dart';
import 'package:vikunja_app/components/TaskTile.dart';
import 'package:vikunja_app/global.dart';
import 'package:vikunja_app/models/list.dart';
import 'package:vikunja_app/models/task.dart';
import 'package:vikunja_app/pages/list/list_edit.dart';

class ListPage extends StatefulWidget {
  final TaskList taskList;

  ListPage({this.taskList}) : super(key: Key(taskList.id.toString()));

  @override
  _ListPageState createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  TaskList _list;
  List<Task> _loadingTasks = [];
  bool _loading = true;
  Future<String> display_done_tasks;
  bool bool_display_done;
  int list_id;

  @override
  void initState() {
    _list = TaskList(
        id: widget.taskList.id, title: widget.taskList.title, tasks: []);
    list_id = _list.id;
    Future.delayed(Duration.zero, (){
      updateDisplayDoneTasks().then((value) => setState((){bool_display_done = value == "1";}));
    });
    super.initState();
  }

  Future<String> updateDisplayDoneTasks() async {
    display_done_tasks = VikunjaGlobal.of(context).getSetting("display_done_tasks_list_$list_id");
    return display_done_tasks;
  }

  @override
  void didChangeDependencies() {
    _loadList();
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: new Text(_list.title),
          actions: <Widget>[
            IconButton(
                icon: Icon(Icons.edit),
                onPressed: ()  =>
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => ListEditPage(
                              list: _list,
                            ))).whenComplete(() {
                              setState(() {this._loading = true;});
                              updateDisplayDoneTasks().then((value) {
                                bool_display_done = value == "1";
                                _loadList();
                                setState(() => this._loading = false);
                              });
                            })
                )
          ],
        ),
        body: !this._loading
            ? RefreshIndicator(
                child: _list.tasks.length > 0
                    ? ListView(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        children: ListTile.divideTiles(
                                context: context, tiles: _listTasks())
                            .toList(),
                      )
                    : Center(child: Text('This list is empty.')),
                onRefresh: _loadList,
              )
            : Center(child: CircularProgressIndicator()),
        floatingActionButton: Builder(
          builder: (context) => FloatingActionButton(
              onPressed: () => _addItemDialog(context), child: Icon(Icons.add)),
        ));
  }

  List<Widget> _listTasks() {
    var tasks = (_list.tasks.map(_buildTile) ?? []).toList();
    //tasks.addAll(_loadingTasks.map(_buildLoadingTile));
    return tasks;
  }

  TaskTile _buildTile(Task task) {
    // key: UniqueKey() seems like a weird workaround to fix the loading issue
    // is there a better way?
    return TaskTile(key: UniqueKey(), task: task,onEdit: () => _loadList());
  }

  Future<void> _loadList() {
    return VikunjaGlobal.of(context)
        .listService
        .get(widget.taskList.id)
        .then((list) {
      setState(() {
        _loading = false;
        if(bool_display_done != null && !bool_display_done)
          list.tasks.removeWhere((element) => element.done);
        _list = list;
      });
    });
  }

  _addItemDialog(BuildContext context) {
    showDialog(
        context: context,
        builder: (_) => AddDialog(
            onAdd: (name) => _addItem(name, context),
            decoration: new InputDecoration(
                labelText: 'Task Name', hintText: 'eg. Milk')));
  }

  _addItem(String name, BuildContext context) {
    var globalState = VikunjaGlobal.of(context);
    var newTask = Task(
        id: null, title: name, owner: globalState.currentUser, done: false, loading: true);
    setState(() => _list.tasks.add(newTask));
    globalState.taskService.add(_list.id, newTask).then((_) {
      _loadList().then((_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('The task was added successfully!'),
        ));
      });
    });
  }
}
