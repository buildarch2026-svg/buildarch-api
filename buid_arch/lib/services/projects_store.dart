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
      _projects = projects;
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

  void clear() {
    _accountGeneration++;
    _projects = [];
    _loading = false;
    _loaded = false;
    _errorMessage = null;
    notifyListeners();
  }
}
