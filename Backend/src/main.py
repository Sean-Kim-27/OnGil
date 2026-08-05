from fastapi import FastAPI

from api.auth.router import router as auth_router

app = FastAPI(title="OnGil API")
app.include_router(auth_router, prefix="/api/v1")
