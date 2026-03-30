from fastapi import FastAPI
from pydantic import BaseModel, Field
import os
import uvicorn

from mlops_house_prices.model import FEATURE_COLUMNS, get_serving_bundle


app = FastAPI(title="house-prices-api", version="0.1.0")
POD_NAME = os.getenv("POD_NAME", os.getenv("HOSTNAME", "unknown"))


class HousePriceRequest(BaseModel):
    overall_qual: float = Field(..., alias="overallQual")
    gr_liv_area: float = Field(..., alias="grLivArea")
    garage_cars: float = Field(..., alias="garageCars")
    total_bsmt_sf: float = Field(..., alias="totalBsmtSF")
    year_built: float = Field(..., alias="yearBuilt")
    full_bath: float = Field(..., alias="fullBath")
    first_flr_sf: float = Field(..., alias="firstFlrSF")
    tot_rms_abv_grd: float = Field(..., alias="totRmsAbvGrd")


@app.get("/")
def root() -> dict:
    bundle = get_serving_bundle()
    return {
        "service": "house-prices-api",
        "podName": POD_NAME,
        "model": "RandomForestRegressor",
        "baselineRmse": round(bundle.rmse, 2),
        "baselineMae": round(bundle.mae, 2),
        "featureNames": FEATURE_COLUMNS,
        "datasetRows": bundle.dataset_rows,
    }


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok", "podName": POD_NAME}


@app.post("/predict")
def predict(payload: HousePriceRequest) -> dict:
    bundle = get_serving_bundle()
    vector = [[
        payload.overall_qual,
        payload.gr_liv_area,
        payload.garage_cars,
        payload.total_bsmt_sf,
        payload.year_built,
        payload.full_bath,
        payload.first_flr_sf,
        payload.tot_rms_abv_grd,
    ]]
    price = float(bundle.model.predict(vector)[0])
    return {
        "predictedSalePrice": round(price, 2),
        "currency": "USD",
    }


if __name__ == "__main__":
    uvicorn.run("mlops_house_prices.serve:app", host="0.0.0.0", port=8000)
