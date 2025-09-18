from typing import TypedDict


class ApplicationParam(TypedDict):
    entity_id: str
    redirect_uri: str
    state: str


# Last updated: 2025-8-19

JWGL_USTB_EDU_CN: ApplicationParam = {
    "entity_id": "NS2022062",
    "redirect_uri": "https://jwgl.ustb.edu.cn/glht/Logon.do?method=weCharLogin",
    "state": "test",
}
"""北京科技大学教务管理系统 2022 年版（已于 2025 年弃用）"""

CHAT_USTB_EDU_CN: ApplicationParam = {
    "entity_id": "YW2025007",
    "redirect_uri": "http://chat.ustb.edu.cn/common/actionCasLogin?redirect_url=http%3A%2F%2Fchat.ustb.edu.cn%2Fpage%2Fsite%2FnewPc%3Flogin_return%3Dtrue",
    "state": "ustb",
}
"""北京科技大学AI助手聊天系统 2025 年版"""

BYYT_USTB_EDU_CN: ApplicationParam = {
    "entity_id": "YW2025006",
    "redirect_uri": "https://byyt.ustb.edu.cn/oauth/login/code",
    "state": "null",
}
"""北京科技大学本研一体教务管理系统 2025 年版"""
