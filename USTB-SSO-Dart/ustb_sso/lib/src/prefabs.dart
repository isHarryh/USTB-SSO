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
  /// 北京科技大学教务管理系统 2022 年版（已于 2025 年弃用）
  static const ApplicationParam jwglUstbEduCn = ApplicationParam(
    entityId: 'NS2022062',
    redirectUri: 'https://jwgl.ustb.edu.cn/glht/Logon.do?method=weCharLogin',
    state: 'test',
  );

  /// 北京科技大学AI助手聊天系统 2025 年版
  static const ApplicationParam chatUstbEduCn = ApplicationParam(
    entityId: 'YW2025007',
    redirectUri:
        'http://chat.ustb.edu.cn/common/actionCasLogin?redirect_url=http%3A%2F%2Fchat.ustb.edu.cn%2Fpage%2Fsite%2FnewPc%3Flogin_return%3Dtrue',
    state: 'ustb',
  );

  /// 北京科技大学本研一体教务管理系统 2025 年版
  static const ApplicationParam byytUstbEduCn = ApplicationParam(
    entityId: 'YW2025006',
    redirectUri: 'https://byyt.ustb.edu.cn/oauth/login/code',
    state: 'null',
  );
}
