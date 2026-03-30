from dataclasses import dataclass
from functools import lru_cache
import os
from pathlib import Path

import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error, root_mean_squared_error
from sklearn.model_selection import train_test_split


FEATURE_COLUMNS = [
    "OverallQual",
    "GrLivArea",
    "GarageCars",
    "TotalBsmtSF",
    "YearBuilt",
    "FullBath",
    "1stFlrSF",
    "TotRmsAbvGrd",
]
TARGET_COLUMN = "SalePrice"
DEFAULT_DATASET_PATH = (
    Path(os.getenv("MLOPS_HOUSE_PRICES_DATA", ""))
    if os.getenv("MLOPS_HOUSE_PRICES_DATA")
    else Path(__file__).resolve().parents[1] / "data" / "ames_housing_selected.csv"
)


@dataclass(frozen=True)
class ModelBundle:
    model: RandomForestRegressor
    rmse: float
    mae: float
    feature_names: list[str]
    dataset_rows: int


def load_dataset() -> pd.DataFrame:
    frame = pd.read_csv(DEFAULT_DATASET_PATH)
    return frame[FEATURE_COLUMNS + [TARGET_COLUMN]].dropna().copy()


def train_model(
    n_estimators: int = 180,
    max_depth: int = 12,
    min_samples_split: int = 4,
    min_samples_leaf: int = 2,
    random_state: int = 42,
) -> ModelBundle:
    frame = load_dataset()
    x_train, x_test, y_train, y_test = train_test_split(
        frame[FEATURE_COLUMNS],
        frame[TARGET_COLUMN].astype(float),
        test_size=0.2,
        random_state=random_state,
    )

    model = RandomForestRegressor(
        n_estimators=n_estimators,
        max_depth=max_depth,
        min_samples_split=min_samples_split,
        min_samples_leaf=min_samples_leaf,
        random_state=random_state,
        n_jobs=-1,
    )
    model.fit(x_train, y_train)
    predictions = model.predict(x_test)

    return ModelBundle(
        model=model,
        rmse=float(root_mean_squared_error(y_test, predictions)),
        mae=float(mean_absolute_error(y_test, predictions)),
        feature_names=FEATURE_COLUMNS,
        dataset_rows=len(frame),
    )


@lru_cache(maxsize=1)
def get_serving_bundle() -> ModelBundle:
    return train_model()
