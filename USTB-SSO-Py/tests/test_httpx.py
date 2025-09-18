from typing import Union, Any, Callable, Type

import os
import traceback
from ustb_sso import HttpxSession, AuthProcedureBase, QrAuthProcedure, SmsAuthProcedure, prefabs


class TestPlatform:
    def __init__(self, name: str, config: Union[prefabs.ApplicationParam, dict], validation_func: Callable[..., bool]):
        self.name = name
        self.config = config
        self.validation_func = validation_func


class TestMethod:
    def __init__(self, name: str, procedure_class: Type, test_func: Callable[..., Any]):
        self.name = name
        self.procedure_class = procedure_class
        self.test_func = test_func


def validate_jwgl_response(**kwargs: Any) -> bool:
    return "//jwgl.ustb.edu.cn/framework" in str(getattr(kwargs["response"], "url", ""))


def validate_chat_response(**kwargs: Any) -> bool:
    return "cookie_vjuid_login" in kwargs["session"].client.cookies


def validate_byyt_response(**kwargs: Any) -> bool:
    print()
    print(kwargs["session"].client.cookies)
    return (
        "//byyt.ustb.edu.cn/" in str(getattr(kwargs["response"], "url", ""))
        and "INCO" in kwargs["session"].client.cookies
        and "SESSION" in kwargs["session"].client.cookies
    )


def test_qr_auth(auth_procedure: QrAuthProcedure, platform: TestPlatform) -> Any:
    print(f"{platform.name}: Setting up QR authentication")

    auth_procedure.use_wechat_auth().use_qr_code()

    qr_path = f"{os.path.dirname(__file__)}/qr.png"
    with open(qr_path, "wb") as f:
        f.write(auth_procedure.get_qr_image())

    print(f"{platform.name}: QR code saved to {qr_path}")
    print(f"{platform.name}: Please scan the QR code to continue")

    pass_code = auth_procedure.wait_for_pass_code()

    print(f"{platform.name}: QR code scanned, completing authentication")
    return auth_procedure.complete_auth(pass_code)


def test_sms_auth(auth_procedure: SmsAuthProcedure, platform: TestPlatform) -> Any:
    print(f"{platform.name}: Setting up SMS authentication")

    try:
        auth_procedure.check_sms_available()
        print(f"{platform.name}: SMS authentication is available")
    except Exception as e:
        print(f"{platform.name}: SMS authentication not available: {e}")
        raise

    phone_number = input(f"Enter phone number for {platform.name} SMS auth: ")

    print(f"{platform.name}: Sending SMS to {phone_number}")
    auth_procedure.send_sms(phone_number)

    sms_code = input(f"Enter SMS verification code for {platform.name}: ")

    print(f"{platform.name}: Received SMS code {sms_code}, verifying")
    token = auth_procedure.submit_sms_code(phone_number, sms_code)

    print(f"{platform.name}: SMS Verified, completing SMS authentication")
    return auth_procedure.complete_sms_auth(token)


PLATFORMS = {
    "JWGL": TestPlatform(name="JWGL", config=prefabs.JWGL_USTB_EDU_CN, validation_func=validate_jwgl_response),
    "CHAT": TestPlatform(name="CHAT", config=prefabs.CHAT_USTB_EDU_CN, validation_func=validate_chat_response),
    "BYYT": TestPlatform(name="BYYT", config=prefabs.BYYT_USTB_EDU_CN, validation_func=validate_byyt_response),
}

METHODS = {
    "QR": TestMethod(name="QR", procedure_class=QrAuthProcedure, test_func=test_qr_auth),
    "SMS": TestMethod(name="SMS", procedure_class=SmsAuthProcedure, test_func=test_sms_auth),
}

# Generate test combinations as ordered pairs
TEST_COMBINATIONS = [(pk, mk) for pk in sorted(PLATFORMS.keys()) for mk in sorted(METHODS.keys())]


def display_auth_methods(auth_procedure, platform_name: str):
    """Display available authentication methods for debugging."""
    if auth_procedure.auth_methods:
        print(f"\n{platform_name}: Available authentication methods:")
        for method in auth_procedure.auth_methods.data:
            print(f"  - {method.chain_name} ({method.module_code})")
        print()


def run_test(platform_key: str, method_key: str):
    """Run a specific platform-method test combination."""
    platform = PLATFORMS[platform_key]
    method = METHODS[method_key]

    print(f"Testing {platform.name} with {method.name} authentication")
    print("=" * 50)

    # Create session and auth procedure
    session = HttpxSession()
    auth_procedure: AuthProcedureBase = method.procedure_class(session=session, **platform.config)

    try:
        # Start authentication
        print(f"{platform.name}: Starting authentication")
        auth_procedure.open_auth()

        # Display available methods for debugging
        print(f"\n{platform.name}: Available authentication methods:")
        for m in auth_procedure.auth_methods.data:
            print(f"  - {m.chain_name} ({m.module_code})")
        print()

        # Run the specific test method
        response = method.test_func(auth_procedure, platform)

        # Validate response
        if platform.validation_func(session=session, response=response):
            print(f"{platform.name}: ✅ Test PASSED - Authentication successful")
        else:
            print(f"{platform.name}: ❌ Test FAILED - Authentication validation failed")

    except Exception as e:
        print(f"{platform.name}: ❌ Test FAILED - Exception: {e}")
        print(f"{platform.name}: 📄 Stack trace:")
        traceback.print_exc()


def test_auth_methods_query():
    print("Testing Authentication Methods Query")
    print("=" * 50)

    session = HttpxSession()
    auth = QrAuthProcedure(session=session, **prefabs.JWGL_USTB_EDU_CN)

    try:
        print("Starting authentication methods query test")
        auth.open_auth()

        if auth.auth_methods:
            print("\nDetailed authentication methods information:")
            for method in auth.auth_methods.data:
                print(f"  Chain: {method.chain_name}")
                print(f"  Module: {method.module_name} ({method.module_code})")
                print()
            sms_method = auth._get_auth_method_by_module_code("userAndSms")
            qr_method = auth._get_auth_method_by_module_code("microQr")

            print("Method availability check:")
            print(f"  - SMS method: {'Okay' if sms_method else 'Not found'}")
            print(f"  - QR method: {'Okay' if sms_method else 'Not found'}")

        print("Authentication methods query: ✅ PASSED")

    except Exception as e:
        print(f"Authentication methods query: ❌ FAILED: {e}")
        print("📄 Stack trace:")
        traceback.print_exc()


def main():
    print("USTB SSO Authentication Test Suite")
    print("=" * 50)

    # Run basic tests first
    test_auth_methods_query()

    # Interactive test selection using ordered pairs
    while True:
        print("=" * 50)
        print("Available test combinations (Platform, Method):")
        for i, (platform_key, method_key) in enumerate(TEST_COMBINATIONS, 1):
            platform_name = PLATFORMS[platform_key].name
            method_name = METHODS[method_key].name
            print(f"{i}. ({platform_key}, {method_key}) - {platform_name} + {method_name} Authentication")

        print(f"{len(TEST_COMBINATIONS) + 1}. Run all tests")
        print(f"{len(TEST_COMBINATIONS) + 2}. Exit")
        print("=" * 50)

        try:
            choice = int(input(f"Select test to run (1-{len(TEST_COMBINATIONS) + 2}): ").strip())

            if 1 <= choice <= len(TEST_COMBINATIONS):
                platform_key, method_key = TEST_COMBINATIONS[choice - 1]
                run_test(platform_key, method_key)
            elif choice == len(TEST_COMBINATIONS) + 1:
                print("\n🚀 Running all test combinations...")
                for platform_key, method_key in TEST_COMBINATIONS:
                    run_test(platform_key, method_key)
            elif choice == len(TEST_COMBINATIONS) + 2:
                print("\n🚫 Exiting test suite.")
                break
            else:
                print(f"Invalid choice. Please select 1-{len(TEST_COMBINATIONS) + 2}.")

        except ValueError:
            print("Invalid input. Please enter a number.")
        except KeyboardInterrupt:
            print("\n🚫 Exiting test suite.")
            break


if __name__ == "__main__":
    main()
