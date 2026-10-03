"""Launch this entry point for the optional web-review experiment."""
from backend.main import app
from backend.review_routes import router

app.include_router(router)
