library;

/// Authentication method information.
class AuthMethod {
  final String? requestNumber;
  final String? requestType;
  final String authChainCode;
  final String chainName;
  final String moduleCode;
  final String moduleName;
  final String moduleNameEn;
  final String moduleNameShortZh;
  final String moduleNameShortEn;
  final String moduleSvg;
  final String moduleLogo;
  final List<String> moduleCodes;

  const AuthMethod({
    this.requestNumber,
    this.requestType,
    required this.authChainCode,
    required this.chainName,
    required this.moduleCode,
    required this.moduleName,
    required this.moduleNameEn,
    required this.moduleNameShortZh,
    required this.moduleNameShortEn,
    required this.moduleSvg,
    required this.moduleLogo,
    required this.moduleCodes,
  });

  factory AuthMethod.fromJson(Map<String, dynamic> json) {
    return AuthMethod(
      requestNumber: json['requestNumber'] as String?,
      requestType: json['requestType'] as String?,
      authChainCode: json['authChainCode'] as String? ?? '',
      chainName: json['chainName'] as String? ?? '',
      moduleCode: json['moduleCode'] as String? ?? '',
      moduleName: json['moduleName'] as String? ?? '',
      moduleNameEn: json['moduleNameEn'] as String? ?? '',
      moduleNameShortZh: json['moduleNameShortZh'] as String? ?? '',
      moduleNameShortEn: json['moduleNameShortEn'] as String? ?? '',
      moduleSvg: json['moduleSvg'] as String? ?? '',
      moduleLogo: json['moduleLogo'] as String? ?? '',
      moduleCodes:
          (json['moduleCodes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'requestNumber': requestNumber,
      'requestType': requestType,
      'authChainCode': authChainCode,
      'chainName': chainName,
      'moduleCode': moduleCode,
      'moduleName': moduleName,
      'moduleNameEn': moduleNameEn,
      'moduleNameShortZh': moduleNameShortZh,
      'moduleNameShortEn': moduleNameShortEn,
      'moduleSvg': moduleSvg,
      'moduleLogo': moduleLogo,
      'moduleCodes': moduleCodes,
    };
  }

  @override
  String toString() =>
      'AuthMethod(chainName: $chainName, moduleCode: $moduleCode)';
}

/// Response for authentication methods query.
class AuthMethodsResponse {
  final List<AuthMethod> data;
  final String? requestNumber;
  final String message;
  final int pageLevelNo;
  final String requestType;
  final bool second;
  final String? userName;
  final String? mobile;
  final String? mail;
  final String lck;
  final String entityId;
  final int code;
  final String? visitUrl;

  const AuthMethodsResponse({
    required this.data,
    this.requestNumber,
    required this.message,
    required this.pageLevelNo,
    required this.requestType,
    required this.second,
    this.userName,
    this.mobile,
    this.mail,
    required this.lck,
    required this.entityId,
    required this.code,
    this.visitUrl,
  });

  factory AuthMethodsResponse.fromJson(Map<String, dynamic> json) {
    final List<dynamic> dataList = json['data'] as List<dynamic>? ?? [];
    final List<AuthMethod> authMethods = dataList
        .map(
          (methodData) =>
              AuthMethod.fromJson(methodData as Map<String, dynamic>),
        )
        .toList();

    return AuthMethodsResponse(
      data: authMethods,
      requestNumber: json['requestNumber'] as String?,
      message: json['message'] as String? ?? '',
      pageLevelNo: json['pageLevelNo'] as int? ?? 0,
      requestType: json['requestType'] as String? ?? '',
      second: json['second'] as bool? ?? false,
      userName: json['userName'] as String?,
      mobile: json['mobile'] as String?,
      mail: json['mail'] as String?,
      lck: json['lck'] as String? ?? '',
      entityId: json['entityId'] as String? ?? '',
      code: json['code'] as int? ?? 0,
      visitUrl: json['visitUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'data': data.map((method) => method.toJson()).toList(),
      'requestNumber': requestNumber,
      'message': message,
      'pageLevelNo': pageLevelNo,
      'requestType': requestType,
      'second': second,
      'userName': userName,
      'mobile': mobile,
      'mail': mail,
      'lck': lck,
      'entityId': entityId,
      'code': code,
      'visitUrl': visitUrl,
    };
  }

  /// Gets authentication method by module code.
  AuthMethod getMethodByModuleCode(String moduleCode) {
    for (final method in data) {
      if (method.moduleCode == moduleCode) {
        return method;
      }
    }
    throw ArgumentError(
      'Module code "$moduleCode" not found in authentication methods.',
    );
  }

  /// Gets authentication methods that contain any of the specified module codes.
  List<AuthMethod> getMethodsByModuleCodes(List<String> moduleCodes) {
    final List<AuthMethod> matchingMethods = [];
    for (final method in data) {
      if (method.moduleCodes.any((code) => moduleCodes.contains(code))) {
        matchingMethods.add(method);
      }
    }
    return matchingMethods;
  }

  @override
  String toString() =>
      'AuthMethodsResponse(code: $code, methods: ${data.length})';
}
