"""NutriChat SDK exceptions."""


class NutriChatError(Exception):
    """Base exception for all NutriChat SDK errors."""

    def __init__(self, message: str, status_code: int | None = None):
        self.message = message
        self.status_code = status_code
        super().__init__(message)


class AuthError(NutriChatError):
    """Raised on 401 — invalid or revoked API key."""

    def __init__(self, message: str = "Invalid or revoked API key"):
        super().__init__(message, status_code=401)


class NotFoundError(NutriChatError):
    """Raised on 404 — food or entry not found."""

    def __init__(self, message: str = "Resource not found"):
        super().__init__(message, status_code=404)


class RateLimitError(NutriChatError):
    """Raised on 429 — rate limit exceeded."""

    def __init__(self, message: str = "Rate limit exceeded", retry_after: float = 60.0):
        self.retry_after = retry_after
        super().__init__(message, status_code=429)
