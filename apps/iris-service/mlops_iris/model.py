from dataclasses import dataclass
from functools import lru_cache

from sklearn.datasets import load_iris
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split


@dataclass(frozen=True)
class ModelBundle:
    model: RandomForestClassifier
    accuracy: float
    feature_names: list[str]
    target_names: list[str]


def train_model(
    n_estimators: int = 80,
    max_depth: int = 4,
    min_samples_split: int = 2,
    random_state: int = 42,
) -> ModelBundle:
    iris = load_iris()
    x_train, x_test, y_train, y_test = train_test_split(
        iris.data,
        iris.target,
        test_size=0.2,
        stratify=iris.target,
        random_state=random_state,
    )

    model = RandomForestClassifier(
        n_estimators=n_estimators,
        max_depth=max_depth,
        min_samples_split=min_samples_split,
        random_state=random_state,
    )
    model.fit(x_train, y_train)
    accuracy = float(model.score(x_test, y_test))

    return ModelBundle(
        model=model,
        accuracy=accuracy,
        feature_names=list(iris.feature_names),
        target_names=list(iris.target_names),
    )


@lru_cache(maxsize=1)
def get_serving_bundle() -> ModelBundle:
    return train_model()

