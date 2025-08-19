USTB-SSO (Py)
==========
USTB Single Sign-On Authentication Library (Python)  
北京科技大学单点登录（SSO）身份认证实现库（Python）

> This module is the Python implementation of [USTB-SSO](https://github.com/isHarryh/USTB-SSO).  
> 此模块是 [USTB-SSO](https://github.com/isHarryh/USTB-SSO) 项目的 Python 实现。

<sup> This project only supports Chinese docs. If you are an English user, feel free to contact us. </sup>

## 介绍 <sub>Intro</sub>

**特点：** 简单易用；自文档化；依赖最少原则；良好的类型注解；全面的错误反馈。

### 实现的功能

- **发起认证：**  
  支持向[北科大 SSO 服务器](https://sso.ustb.edu.cn)发起针对指定应用的身份认证请求；
- **进行认证：**  
  支持使用微信二维码或短信验证码来完成身份认证；
- **完成认证：**  
  支持在认证成功后，获取已被认证的客户端实例或 Cookie 实例。

## 使用方法 <sub>Usage</sub>

### 安装

要求 [Python](https://www.python.org) >= 3.8，且安装有 [httpx](https://www.python-httpx.org/) 库（一个类似于 requests 的库）。使用 `pip` 安装：

```bash
pip install httpx ustb_sso
```

### 前置知识

要想实现通过 SSO 来北科大的某个指定的应用，需要先准备 3 个参数：

1. 该应用的实体编号（`entity_id`）；
2. 该应用的认证终点 URL（`redirect_uri`）；
3. 该应用的内部状态名（`state`）。

我们已经在 `ustb_sso.prefabs` 中以常量的形式存储了部分已知应用的参数。如果您需要接入其他应用，请自行在网页中抓取 `https://sso.ustb.edu.cn/idp/authCenter/authenticate` 这个请求的请求参数来获得。

### 示例：微信扫码登录

以下代码演示了如何通过通过微信扫码登录来获取[北科大 AI 助手](http://chat.ustb.edu.cn)（2025 年版）的令牌 Cookie。

```py
import os
from ustb_sso import HttpxSession, QrAuthProcedure, prefabs

session = HttpxSession()
auth = QrAuthProcedure(session=session, **prefabs.CHAT_USTB_EDU_CN)  # ※

print("Starting authentication...")
auth.open_auth()
auth.use_wechat_auth().use_qr_code()

with open(f"qr.png", "wb") as f:
    f.write(auth.get_qr_image())  # ▲

print("Waiting for confirmation... Please scan the QR code")
pass_code = auth.wait_for_pass_code()

print("Validating...")
rsp = auth.complete_auth(pass_code)

print("Response status:", rsp.status_code)
cookie_name = "cookie_vjuid_login"
print("Cookie:", cookie_name, "=", session.client.cookies[cookie_name])
```

当代码运行到 `▲` 位置时，您需要使用微信来扫描文件夹中生成的 `qr.png` 图片中的二维码，并在微信上确认登录。

代码的 `※` 位置使用了字典解包（`**`）操作符。它等价于：

```python
auth = HttpxAuthSession(
    entity_id=prefabs.CHAT_USTB_EDU_CN["entity_id"],
    redirect_uri=prefabs.CHAT_USTB_EDU_CN["redirect_uri"],
    state=prefabs.CHAT_USTB_EDU_CN["state"]
)
```

这里的 `prefabs.CHAT_USTB_EDU_CN` 就是我们的库所提供的预设应用参数，以便开发者快捷调用。有关其他的预设应用参数，请参见[此文件](ustb_sso/_prefabs.py)。

`session.client` 是一个 `httpx.Client` 实例（类似于 `request.Session`），用于存储 Cookie 等客户端数据。后续如果需要使用 Cookie 令牌去做其他的 API 请求，可以直接调用 `session.client` 的相关方法。

### 示例：短信验证码登录

如果没有微信扫码的条件，则可以使用短信验证码进行登录。以下是使用短信验证码进行登录的示例。

```py
from ustb_sso import HttpxSession, SmsAuthProcedure, prefabs

session = HttpxSession()
auth = SmsAuthProcedure(session=session, **prefabs.CHAT_USTB_EDU_CN)

print("Starting authentication...")
auth.open_auth()
auth.check_sms_available()

phone_number = input("Please enter your phone number: ")
auth.send_sms(phone_number)

sms_code = input("Please enter the SMS code: ")
token = auth.submit_sms_code(phone_number, sms_code)

print("Validating...")
rsp = auth.complete_sms_auth(token)

print("Response status:", rsp.status_code)
cookie_name = "cookie_vjuid_login"
print("Cookie:", cookie_name, "=", session.client.cookies[cookie_name])
```

## 开发指南 <sub>Dev Guide</sub>

如果您想对 USTB-SSO (Py) 进行开发，以下指引可能有所帮助。

### 开始开发

1. 安装 Python；
2. 安装依赖管理工具 [Poetry](https://python-poetry.org/docs) 2.1；
3. 克隆仓库到本地；
4. 使用 Poetry 创建虚拟环境，并安装所有依赖项：
   ```bash
   poetry env use python
   poetry install -E httpx
   ```

### 测试

1. 激活虚拟环境：
   - 在 VS Code 中选择虚拟环境中的 Python 解释器（推荐）；
   - 或者，使用 `poetry shell` 命令进入虚拟环境。
2. 运行测试代码：
   - 在 VS Code 中运行任务 `Python: Test USTB-SSO`（推荐）；
   - 或者，使用 `python <文件名>` 命令来手动运行代码。
3. 构建可发行文件：
   ```bash
   poetry build
   ```

## 许可证 <sub>Licensing</sub>

本项目基于 **MIT 开源许可证**，详情参见 [License](https://github.com/isHarryh/USTB-SSO/blob/main/LICENSE) 页面。
