"""
Data models for USTB SSO authentication.
"""

from typing import List, Optional
from dataclasses import dataclass


@dataclass
class AuthMethod:
    """Authentication method information."""

    request_number: Optional[str]
    request_type: Optional[str]
    auth_chain_code: str
    chain_name: str
    module_code: str
    module_name: str
    module_name_en: str
    module_name_short_zh: str
    module_name_short_en: str
    module_svg: str
    module_logo: str
    module_codes: List[str]


@dataclass
class AuthMethodsResponse:
    """Response for authentication methods query."""

    data: List[AuthMethod]
    request_number: Optional[str]
    message: str
    page_level_no: int
    request_type: str
    second: bool
    user_name: Optional[str]
    mobile: Optional[str]
    mail: Optional[str]
    lck: str
    entity_id: str
    code: int
    visit_url: Optional[str]

    @classmethod
    def from_dict(cls, data: dict) -> "AuthMethodsResponse":
        """Create AuthMethodsResponse from dictionary."""
        auth_methods = []
        for method_data in data.get("data", []):
            method_data: dict
            auth_method = AuthMethod(
                request_number=method_data.get("requestNumber"),
                request_type=method_data.get("requestType"),
                auth_chain_code=method_data.get("authChainCode", ""),
                chain_name=method_data.get("chainName", ""),
                module_code=method_data.get("moduleCode", ""),
                module_name=method_data.get("moduleName", ""),
                module_name_en=method_data.get("moduleNameEn", ""),
                module_name_short_zh=method_data.get("moduleNameShortZh", ""),
                module_name_short_en=method_data.get("moduleNameShortEn", ""),
                module_svg=method_data.get("moduleSvg", ""),
                module_logo=method_data.get("moduleLogo", ""),
                module_codes=method_data.get("moduleCodes", []),
            )
            auth_methods.append(auth_method)

        return cls(
            data=auth_methods,
            request_number=data.get("requestNumber"),
            message=data.get("message", ""),
            page_level_no=data.get("pageLevelNo", 0),
            request_type=data.get("requestType", ""),
            second=data.get("second", False),
            user_name=data.get("userName"),
            mobile=data.get("mobile"),
            mail=data.get("mail"),
            lck=data.get("lck", ""),
            entity_id=data.get("entityId", ""),
            code=data.get("code", 0),
            visit_url=data.get("visitUrl"),
        )

    def get_method_by_module_code(self, module_code: str) -> AuthMethod:
        """Get authentication method by module code."""
        for method in self.data:
            if method.module_code == module_code:
                return method
        raise KeyError(f"Module code '{module_code}' not found in authentication methods.")

    def get_methods_by_module_codes(self, module_codes: List[str]) -> List[AuthMethod]:
        """Get authentication methods that contain any of the specified module codes."""
        matching_methods = []
        for method in self.data:
            if any(code in method.module_codes for code in module_codes):
                matching_methods.append(method)
        return matching_methods
