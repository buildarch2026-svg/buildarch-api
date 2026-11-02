import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/project.dart';
import '../models/project_type.dart';
import 'auth_api_service.dart';
import 'auth_session_service.dart';

/// Holds the signed-in user's server-backed projects for the current session.
class ProjectsStore extends ChangeNotifier {
  ProjectsStore._();
  static final ProjectsStore instance = ProjectsStore._();

  List<Project> _projects = [];
  bool _loading = false;
  bool _loaded = false;
  String? _errorMessage;
  int _accountGeneration = 0;

  List<Project> get projects => List.unmodifiable(_projects);

  bool get isEmpty => _projects.isEmpty;
  bool get isLoading => _loading;
  bool get hasLoaded => _loaded;
  String? get errorMessage => _errorMessage;

  Future<void> load({bool refresh = false}) async {
    if (_loading || (_loaded && !refresh)) return;
    final accountGeneration = _accountGeneration;
    _loading = true;
    _errorMessage = null;
    if (refresh) {
      _projects = [];
      _loaded = false;
    }
    notifyListeners();

    try {
      final token = await AuthSessionService.instance.readToken();
      if (token == null || token.isEmpty) {
        throw const AuthApiException(
          'Your session expired. Please sign in again.',
        );
      }
      final projects = await AuthApiService.instance.getProjects(token: token);
      if (accountGeneration != _accountGeneration) return;
      _projects = projects.where((project) => !project.isDeleted).toList();
      _loaded = true;
    } on AuthApiException catch (error) {
      if (accountGeneration != _accountGeneration) return;
      _errorMessage = error.message;
    } catch (_) {
      if (accountGeneration != _accountGeneration) return;
      _errorMessage = 'Could not load projects. Please try again.';
    } finally {
      if (accountGeneration == _accountGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> create({
    required String name,
    required String location,
    required ProjectType type,
    double? latitude,
    double? longitude,
    XFile? photo,
  }) async {
    final accountGeneration = _accountGeneration;
    final token = await AuthSessionService.instance.readToken();
    if (token == null || token.isEmpty) {
      throw const AuthApiException(
        'Your session expired. Please sign in again.',
      );
    }

    final project = await AuthApiService.instance.createProject(
      token: token,
      name: name,
      location: location,
      type: type,
      latitude: latitude,
      longitude: longitude,
      photo: photo,
    );
    if (accountGeneration != _accountGeneration) return;
    _projects = [project, ..._projects];
    _loaded = true;
    _errorMessage = null;
    notifyListeners();
  }

  Future<Project> updatePhoto({
    required String projectId,
    required XFile photo,
  }) async {
    final accountGeneration = _accountGeneration;
    final token = await AuthSessionService.instance.readToken();
    if (token == null || token.isEmpty) {
      throw const AuthApiException(
        'Your session expired. Please sign in again.',
      );
    }

    final project = await AuthApiService.instance.uploadProjectPhoto(
      token: token,
      projectId: projectId,
      photo: photo,
    );
    if (accountGeneration != _accountGeneration) return project;

    final projectIndex = _projects.indexWhere((item) => item.id == projectId);
    if (projectIndex != -1) {
      _projects[projectIndex] = project;
      notifyListeners();
    }
    return project;
  }

  Future<Project> updateProject({
    required String projectId,
    required String name,
    required String location,
    required ProjectType type,
    double? latitude,
    double? longitude,
  }) async {
    final accountGeneration = _accountGeneration;
    final token = await AuthSessionService.instance.readToken();
    if (token == null || token.isEmpty) {
      throw const AuthApiException(
        'Your session expired. Please sign in again.',
      );
    }

    final project = await AuthApiService.instance.updateProject(
      token: token,
      projectId: projectId,
      name: name,
      location: location,
      type: type,
      latitude: latitude,
      longitude: longitude,
    );
    if (accountGeneration != _accountGeneration) return project;
    _replaceProject(project);
    return project;
  }

  Future<void> archiveProject(String projectId) async {
    await _runProjectAction(
      projectId,
      AuthApiService.instance.archiveProject,
    );
  }

  Future<void> deleteProject(String projectId) async {
    await _runProjectAction(
      projectId,
      AuthApiService.instance.deleteProject,
    );
  }

  Future<void> restoreProject(String projectId) async {
    await _runProjectAction(
      projectId,
      AuthApiService.instance.restoreProject,
    );
  }

  Future<void> _runProjectAction(
    String projectId,
    Future<Project> Function({
      required String token,
      required String projectId,
    }) action,
  ) async {
    final accountGeneration = _accountGeneration;
    final token = await AuthSessionService.instance.readToken();
    if (token == null || token.isEmpty) {
      throw const AuthApiException(
        'Your session expired. Please sign in again.',
      );
    }

    final project = await action(token: token, projectId: projectId);
    if (accountGeneration == _accountGeneration) _replaceProject(project);
  }

  void _replaceProject(Project project) {
    if (project.isDeleted) {
      _projects.removeWhere((item) => item.id == project.id);
      _loaded = true;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    final projectIndex = _projects.indexWhere((item) => item.id == project.id);
    if (projectIndex == -1) {
      _projects = [project, ..._projects];
    } else {
      _projects[projectIndex] = project;
    }
    _loaded = true;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> removeProjectMember({
    required String projectId,
    required int memberUserId,
  }) async {
    final token = await AuthSessionService.instance.readToken();
    if (token == null || token.isEmpty) {
      throw const AuthApiException(
        'Your session expired. Please sign in again.',
      );
    }
    await AuthApiService.instance.removeProjectMember(
      token: token,
      projectId: projectId,
      memberUserId: memberUserId,
    );
  }

  void clear() {
    _accountGeneration++;
    _projects = [];
    _loading = false;
    _loaded = false;
    _errorMessage = null;
    notifyListeners();
  }
}
