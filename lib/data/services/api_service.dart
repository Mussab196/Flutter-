import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../core/constants/api_endpoints.dart';
import '../../core/constants/app_constants.dart';
import '../models/api_response_model.dart';

/// API Service for HTTP requests
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _accessToken;

  /// Set access token for authenticated requests
  void setAccessToken(String? token) {
    _accessToken = token;
  }

  /// Get common headers
  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  /// GET request
  Future<ApiResponse<T>> get<T>(
    String endpoint, {
    Map<String, String>? queryParams,
    T Function(dynamic)? fromJsonT,
  }) async {
    try {
      final uri = Uri.parse('${ApiEndpoints.baseUrl}$endpoint')
          .replace(queryParameters: queryParams);

      final response = await http.get(uri, headers: _headers).timeout(
          const Duration(milliseconds: AppConstants.connectionTimeout));

      return _handleResponse(response, fromJsonT);
    } on SocketException {
      return ApiResponse.error(message: 'No internet connection');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  /// POST request
  Future<ApiResponse<T>> post<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJsonT,
  }) async {
    try {
      final uri = Uri.parse('${ApiEndpoints.baseUrl}$endpoint');

      final response = await http
          .post(
            uri,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(
              const Duration(milliseconds: AppConstants.connectionTimeout));

      return _handleResponse(response, fromJsonT);
    } on SocketException {
      return ApiResponse.error(message: 'No internet connection');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  /// PUT request
  Future<ApiResponse<T>> put<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromJsonT,
  }) async {
    try {
      final uri = Uri.parse('${ApiEndpoints.baseUrl}$endpoint');

      final response = await http
          .put(
            uri,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(
              const Duration(milliseconds: AppConstants.connectionTimeout));

      return _handleResponse(response, fromJsonT);
    } on SocketException {
      return ApiResponse.error(message: 'No internet connection');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  /// DELETE request
  Future<ApiResponse<T>> delete<T>(
    String endpoint, {
    T Function(dynamic)? fromJsonT,
  }) async {
    try {
      final uri = Uri.parse('${ApiEndpoints.baseUrl}$endpoint');

      final response = await http.delete(uri, headers: _headers).timeout(
          const Duration(milliseconds: AppConstants.connectionTimeout));

      return _handleResponse(response, fromJsonT);
    } on SocketException {
      return ApiResponse.error(message: 'No internet connection');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  /// Multipart POST (for file uploads)
  Future<ApiResponse<T>> uploadFile<T>(
    String endpoint, {
    required File file,
    required String fieldName,
    Map<String, String>? fields,
    T Function(dynamic)? fromJsonT,
  }) async {
    try {
      final uri = Uri.parse('${ApiEndpoints.baseUrl}$endpoint');
      final request = http.MultipartRequest('POST', uri);

      request.headers.addAll(_headers);
      request.files
          .add(await http.MultipartFile.fromPath(fieldName, file.path));

      if (fields != null) {
        request.fields.addAll(fields);
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      return _handleResponse(response, fromJsonT);
    } on SocketException {
      return ApiResponse.error(message: 'No internet connection');
    } catch (e) {
      return ApiResponse.error(message: e.toString());
    }
  }

  /// Handle HTTP response
  ApiResponse<T> _handleResponse<T>(
    http.Response response,
    T Function(dynamic)? fromJsonT,
  ) {
    final body = jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return ApiResponse.fromJson(body, fromJsonT);
    } else {
      return ApiResponse.error(
        message: body['message'] ?? 'Request failed',
        statusCode: response.statusCode,
        errors: body['errors'],
      );
    }
  }
}
