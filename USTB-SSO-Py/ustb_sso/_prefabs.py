from typing import TypedDict


class ApplicationParam(TypedDict):
    entity_id: str
    redirect_uri: str
    state: str

# Last updated: 2025-2-28

JWGL_USTB_EDU_CN: ApplicationParam = {
    "entity_id": "NS2022062",
    "redirect_uri": "https://jwgl.ustb.edu.cn/glht/Logon.do?method=weCharLogin",
    "state": "test"
}

CHAT_USTB_EDU_CN: ApplicationParam = {
    "entity_id": "YW2025007",
    "redirect_uri": "http://chat.ustb.edu.cn/common/actionCasLogin?redirect_url=http%3A%2F%2Fchat.ustb.edu.cn%2Fpage%2Fsite%2FnewPc%3Flogin_return%3Dtrue",
    "state": "ustb"
}
