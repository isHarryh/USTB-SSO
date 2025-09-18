library;

/// Application parameter configuration.
class ApplicationParam {
  final String entityId;
  final String redirectUri;
  final String state;

  const ApplicationParam({
    required this.entityId,
    required this.redirectUri,
    required this.state,
  });

  Map<String, dynamic> toJson() {
    return {'entityId': entityId, 'redirectUri': redirectUri, 'state': state};
  }

  @override
  String toString() => 'ApplicationParam(entityId: $entityId, state: $state)';
}

/// Pre-configured application parameters for common USTB services.
class Prefabs {
  /// 北科大教务管理系统
  static const ApplicationParam jwglUstbEduCn = ApplicationParam(
    entityId: 'NS2022062',
    redirectUri: 'https://jwgl.ustb.edu.cn/glht/Logon.do?method=weCharLogin',
    state: 'test',
  );

  /// 北科大AI助手 (2025年版)
  static const ApplicationParam chatUstbEduCn = ApplicationParam(
    entityId: 'YW2025007',
    redirectUri:
        'http://chat.ustb.edu.cn/common/actionCasLogin?redirect_url=http%3A%2F%2Fchat.ustb.edu.cn%2Fpage%2Fsite%2FnewPc%3Flogin_return%3Dtrue',
    state: 'ustb',
  );
}
