from fastapi import FastAPI
from pydantic import BaseModel, Field
import os
import uvicorn

from mlops_iris.model import get_serving_bundle


app = FastAPI(title="iris-ml-api", version="0.1.0")
POD_NAME = os.getenv("POD_NAME", os.getenv("HOSTNAME", "unknown"))


class IrisRequest(BaseModel):
    sepal_length: float = Field(..., alias="sepalLength")
    sepal_width: float = Field(..., alias="sepalWidth")
    petal_length: float = Field(..., alias="petalLength")
    petal_width: float = Field(..., alias="petalWidth")


@app.get("/")
def root() -> dict:
    bundle = get_serving_bundle()
    return {
        "service": "iris-ml-api",
        "podName": POD_NAME,
        "model": "RandomForestClassifier",
        "baselineAccuracy": round(bundle.accuracy, 4),
        "featureNames": bundle.feature_names,
        "targetNames": bundle.target_names,
    }


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok", "podName": POD_NAME}


@app.post("/predict")
def predict(payload: IrisRequest) -> dict:
    bundle = get_serving_bundle()
    vector = [[
        payload.sepal_length,
        payload.sepal_width,
        payload.petal_length,
        payload.petal_width,
    ]]
    prediction = int(bundle.model.predict(vector)[0])
    probabilities = bundle.model.predict_proba(vector)[0]
    return {
        "classId": prediction,
        "className": bundle.target_names[prediction],
        "probabilities": {
            bundle.target_names[index]: round(float(probability), 4)
            for index, probability in enumerate(probabilities)
        },
    }


if __name__ == "__main__":
    uvicorn.run("mlops_iris.serve:app", host="0.0.0.0", port=8000)
