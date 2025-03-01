import os

from ustb_sso import HttpxAuthSession, prefabs

def test_jwgl():
    auth = HttpxAuthSession(**prefabs.JWGL_USTB_EDU_CN)

    print("JWGL: Starting authentication")
    auth.open_auth().use_wechat_auth().use_qr_code()

    with open(f"{os.path.dirname(__file__)}/qr.png", "wb") as f:
        f.write(auth.get_qr_image())

    print("JWGL: Waiting, please scan the QR code")
    pass_code = auth.wait_for_pass_code()

    print("JWGL: Validating")
    rsp = auth.complete_auth(pass_code)

    assert "//jwgl.ustb.edu.cn/framework" in str(rsp.url), "No homepage returned"
    print("JWGL: Finished test\n")

def test_chat():
    auth = HttpxAuthSession(**prefabs.CHAT_USTB_EDU_CN)

    print("CHAT: Starting authentication")
    auth.open_auth().use_wechat_auth().use_qr_code()

    with open(f"{os.path.dirname(__file__)}/qr.png", "wb") as f:
        f.write(auth.get_qr_image())

    print("CHAT: Waiting, please scan the QR code")
    pass_code = auth.wait_for_pass_code()

    print("CHAT: Validating")
    rsp = auth.complete_auth(pass_code)

    assert "cookie_vjuid_login" in auth.client.cookies, "No authentication cookie returned"
    print("CHAT: Finished test\n")


if __name__ == "__main__":
    test_jwgl()
    test_chat()
