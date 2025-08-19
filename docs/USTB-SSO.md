USTB SSO 附加文档

# USTB SSO 逆向工程解析

此文档记载了针对北京科技大学单点登录（SSO）系统的逆向解析。

> 请注意内容的时效性！随着系统的升级，这些内容可能不再有效。
>
> - 初稿：2025 年 2 月

> 下文中出现的名词，例如“认证入口”、“认证出口”、“认证终点”、“认证 ID”和“通行码”等，均由作者命名，主要是便于表述和理解。

## 标准认证流程

下面介绍标准认证的工作流程和 API。

### 认证入口

#### GET `https://sso.ustb.edu.cn/idp/authCenter/authenticate`

- 功能：认证入口点。访问后重定向到一个认证页面。
- 请求参数：
  - `client_id` 客户端应用的标识符，例如[教务管理系统](#教务管理系统)的标识符为 `NS2022062`。
  - `redirect_uri` 认证成功后的跳转目标，即认证终点。
  - `login_return` 默认 `true`。
  - `state` 常见有 `ustb` `test` 等，依应用而异。
  - `response_type` 默认 `code`。
- 响应：重定向 `302 Found`。响应头的 `Location` 字段是指向认证页面的 URL，以 `https://sso.ustb.edu.cn/ac/#/index` 开头，其查询字符串中包含以下重要信息：
  - `lck` 其值为 `context_oauth2_<32个字符>`，是本次认证的 ID。
  - `entityId` 实体标识符，等同于 `client_id`。

### 微信登录

#### POST `https://sso.ustb.edu.cn/idp/authn/getMicroQr`

- 功能：创建一个微信二维码认证，并取得认证凭据。
- 请求参数：
  - `entityId` 实体标识符。
  - `lck` 本次认证的 ID。
- 响应：JSON。根字段包括 `code` `status` `message` `data`，其中 `code == "200"` 表示成功。
- 响应结构：`data` 字段包含以下重要信息：
  - `appId` 凭据 ID，其值为 `<32个字符>`。
  - `returnUrl` [认证出口的 URL](#get-httpsssoustbeducnidpauthcenterthirdpartyauthengine)，以 `https://sso.ustb.edu.cn/idp/authCenter/authenticateByLck` 开头（可能包含查询字符串）。
  - `url` [二维码展示页面的 URL](#get-httpssisustbeducnconnectqrpage)，默认 `https://sis.ustb.edu.cn/connect/qrpage`。
  - `randomToken` 其值为 `<32个字符>`，是服务器端生成的随机标识符。
- 注意：请求体使用 JSON 格式传参。

#### GET `https://sis.ustb.edu.cn/connect/qrpage`

- 功能：获得用于展示二维码的嵌入式页面。
- 请求参数：
  - `appid` 等同于 `appId`。
  - `return_url` 等同于 `returnUrl`。
  - `rand_token` 等同于 `randomToken`。
  - `embed_flag` 默认 `1`。
- 响应：HTML。
- 响应结构：HTML 中包含一个会话 ID（即 `sid`，其值为 `<32个字符>`），需要使用正则表达式 `sid\s?=\s?(\w{32})` 来提取。
- 注意：每个会话 ID 的有效期约为 3 分钟。

#### GET `https://sis.ustb.edu.cn/connect/qrimg`

- 功能：获取微信二维码认证的图片。
- 请求参数：
  - `sid` 会话 ID。
- 响应：PNG。

#### GET `https://sis.ustb.edu.cn/connect/state`

- 功能：实时获取微信二维码认证的状态，前端处理逻辑参见 [mas.js](https://sis.ustb.edu.cn/js/mas.js)。
- 请求参数：
  - `sid` 会话 ID。
- 响应：JSON。根字段包括 `code` `data` `message`。
- 响应结构：常见的 `code` 对应的状态如下：
  - `code == 1` 已在微信端进行确认，认证成功。此时 `data` 字段存有一个 `<32个字符>` 组成的通行码。
  - `code == 2` 已扫码，但尚未确认。
  - `code == 3 || code == 202` 已失效。
  - `code == 4` 请求超时。
  - `code == 101 || code == 102` 请求不合法。
- 注意：每次发起请求时，如果认证状态没有变更，那么请求会挂起约 15 秒，直到状态发生变更或请求超时。

### 认证出口

#### GET `https://sso.ustb.edu.cn/idp/authCenter/thirdPartyAuthEngine`

- 功能：认证成功后的认证出口页。访问此页会进行一系列的重定向，最终会重定向到客户端应用的登录接口（认证终点）。
- 请求参数：
  - `thirdPartyAuthCode` 常见的有 `microQr`。
  - `lck` 本次认证的 ID。
  - `appid` 等同于 `appId`。
  - `auth_code` 通行码。
  - `rand_token` 等同于 `randomToken`。
- 响应：重定向 `302 Found`。具体目标依应用而异，参见[各应用的认证终点](#各应用的认证终点)。
- 注意：请求参数中，`thirdPartyAuthCode` 和 `lck` 通常已经给出，只需手动添加剩余的参数。

## 认证方式查询

在启动任何具体的认证流程之前，系统需要查询当前实体支持的认证方式。

### 查询认证方式

#### POST `https://sso.ustb.edu.cn/idp/authn/queryAuthMethods`

- 功能：查询指定实体支持的认证方式列表。
- 请求参数：
  - `lck` 本次认证的 ID。
  - `entityId` 实体标识符。
- 响应：JSON。根字段包括 `code` `data` `message` 等，其中 `code == 200` 表示成功。
- 响应结构：`data` 字段是一个数组，每个元素包含以下重要信息：
  - `authChainCode` 认证链代码。
  - `chainName` 认证方式的中文名称，例如"短信认证-定制"、"微认证扫码-需要同时配置微认证sso"。
  - `moduleCode` 模块代码，例如 `userAndSms`（短信认证）、`microQr`（微信二维码认证）。
  - `moduleName` 模块名称，例如"验证码登录"、"微信登录"。
  - `moduleNameEn` 模块英文名称。
  - `moduleCodes` 模块代码列表，通常包含单个 `moduleCode`。
- 注意：此接口必须在获取 `lck` 后调用，通常在[认证入口](#认证入口)步骤之后立即执行。

## 短信认证流程

短信认证是除微信扫码外的另一种主要认证方式。该流程需要用户提供手机号码，系统发送验证码到用户手机，用户输入验证码完成认证。

### 检查短信认证可用性

#### GET `https://sso.ustb.edu.cn/idp/captcha/checkOpen`

- 功能：检查指定类型的验证码是否可用。
- 请求参数：
  - `type` 验证码类型，短信认证时使用 `sms`。
- 响应：状态码 `200` 表示该类型验证码可用。

### 获取图形验证码

#### GET `https://sso.ustb.edu.cn/idp/captcha/getBlockPuzzle`

- 功能：获取滑动拼图验证码，用于短信发送前的人机验证。
- 请求参数：无。
- 响应：JSON。根字段包括 `code` `data` `message` 等。
- 响应结构：`data` 字段包含以下重要信息：
  - `originalImageBase64` 原始背景图片的 Base64 编码。
  - `jigsawImageBase64` 拼图块图片的 Base64 编码。
  - `token` 验证码会话标识符，UUID 格式。
- 注意：客户端需要计算拼图块在背景图片中的正确位置坐标 `(x, y)`，可使用图像识别算法或第三方库（如 `no_puzzle_captcha`）自动求解。

### 发送短信验证码

#### POST `https://sso.ustb.edu.cn/idp/authn/sendSmsMsg`

- 功能：向指定手机号发送短信验证码。
- 请求参数：
  - `loginName` 手机号码字符串。
  - `pointJson` 拼图验证的答案，JSON 字符串格式，包含 `x` 和 `y` 坐标，例如 `"{\"x\":123,\"y\":5}"`。
  - `token` 从[图形验证码](#获取图形验证码)获取的会话标识符。
  - `lck` 本次认证的 ID。
- 响应：JSON。根字段包括 `code` `data` `message` 等。
- 响应结构：成功时 `data.data.code == "200"`。常见错误码：
  - `201` 发送间隔过短，需要等待。
  - `5054` 图形验证不通过，拼图坐标错误。
- 注意：请求体使用 JSON 格式传参。发送成功后，用户手机将收到包含验证码的短信。

### 短信验证码认证

#### POST `https://sso.ustb.edu.cn/idp/authn/authExecute`

- 功能：使用短信验证码完成身份认证。
- 请求参数：
  - `authModuleCode` 认证模块代码，短信认证时固定为 `userAndSms`。
  - `authChainCode` 认证链代码，通常为空字符串。
  - `entityId` 实体标识符。
  - `requestType` 请求类型，固定为 `chain_type`。
  - `lck` 本次认证的 ID。
  - `authPara` 认证参数对象，包含：
    - `loginName` 手机号码。
    - `smsCode` 用户输入的短信验证码。
    - `verifyCode` 图形验证码，短信认证时通常为空字符串。
- 响应：JSON。包含认证结果和相关信息。
- 注意：请求体使用 JSON 格式传参。认证成功后，响应将包含进一步跳转所需的信息。

## 各应用的认证终点

认证终点，即客户端应用的登录接口，其作用是为客户端应用赋予用户令牌（通常以 Cookie 的形式）。

通常情况下，在[标准认证流程](#标准认证流程)结束后，[认证出口](#认证出口)就会将页面重定向到认证终点。随后，认证终点授予（应用特异性的）令牌，跳转到应用的主页。这样就完成了转接工作。

下面列出了一些官方应用的认证终点的逻辑。

### 教务管理系统

本科生教务管理系统：内网访问 https://jwgl.ustb.edu.cn ，实体标识符 `NS2022062`。

游客访问此系统时，会授予一个随机令牌 `JSESSIONID`。用户需要携带该令牌抵达认证终点的第一次跳转，才能将令牌的权限升级为对应的认证用户的权限（令牌有效化）。

#### 认证终点

教务管理系统的认证终点是一个 HTML，内容概述如下：

```html
<html>
  <head>
    <meta http-equiv="X-UA-Compatible" content="IE=11,chrome=1">
    <script>
        function doSubmit() {
            var actionType = "GET";
            var locationValue = "https://jwgl.ustb.edu.cn/glht/Logon.do?method=weCharLogin&amp;code=...&amp;state=test";
            locationValue = escape2Html(locationValue);
            if (actionType == "POST"){
                var logon = document.getElementById("logon");
                logon.submit();
            } else {
                location = locationValue;
            }
        }
        function escape2Html(str) { return ...; }
    </script>
  </head>

  <body onload="doSubmit()">
    <form id="logon" method="GET" action="https://jwgl.ustb.edu.cn/glht/Logon.do?method=weCharLogin" target="_self">
      <tr>
        <input type="hidden" id="code" name="code" value="..."></input>
      </tr>
      <tr>
        <input type="hidden" id="state" name="state" value="test"></input>
      </tr>
    </form>
  </body>
</html>
```

第一次跳转：认证终点会以 `GET` 方式跳转到 `https://jwgl.ustb.edu.cn/glht/Logon.do`，并通过表单提交的方式传递一个 `code` 参数。

> **GET `https://jwgl.ustb.edu.cn/glht/Logon.do`**
> 
> - 请求参数：
>   - `method` 默认 `weCharLogin`。
>   - `code` 最终通行码。
>   - `state` 这里固定是 `test`。

第二次跳转：`/glht/Logon.do` 会跳转到 `/xk/LoginToXk`。此时，用户携带的令牌已被有效化。

第三次跳转：`/xk/LoginToXk` 会跳转到 `/framework/xsMain_bjkjdx.jsp`，也就是教务管理的主页。

### 北科大 AI 助手

北科大 AI 助手：内网访问 http://chat.ustb.edu.cn ，实体标识符 `YW2025007`。

认证终点的第一次跳转，会赋予用户一个 Cookie 令牌 `cookie_vjuid_login`。携带此令牌即可访问北科大 AI 助手的任意功能。

#### 认证终点

北科大 AI 助手的认证终点也是一个类似的 HTML，只是第一次跳转的目标和参数有少许变化。

第一次跳转：`http://chat.ustb.edu.cn/common/actionCasLogin`。响应后，用户会被赋予 Cookie 令牌。

> **GET `http://chat.ustb.edu.cn/common/actionCasLogin`**
> 
> - 请求参数：
>   - `redirect_url` 默认 `http://chat.ustb.edu.cn/page/site/newPc?login_return=true`。
>   - `code` 最终通行码。
>   - `state` 这里固定是 `ustb`。

第二次跳转：跳转到上述 `redirect_url` 的位置。
