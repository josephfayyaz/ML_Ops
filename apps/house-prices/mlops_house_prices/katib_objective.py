import argparse
import time

from mlops_house_prices.model import train_model


def main() -> None:
    parser = argparse.ArgumentParser(description="Katib objective for the house-prices demo")
    parser.add_argument("--n-estimators", type=int, required=True)
    parser.add_argument("--max-depth", type=int, required=True)
    parser.add_argument("--min-samples-split", type=int, required=True)
    parser.add_argument("--min-samples-leaf", type=int, required=True)
    args = parser.parse_args()

    bundle = train_model(
        n_estimators=args.n_estimators,
        max_depth=args.max_depth,
        min_samples_split=args.min_samples_split,
        min_samples_leaf=args.min_samples_leaf,
    )

    print(
        "trial="
        f"n_estimators:{args.n_estimators},"
        f"max_depth:{args.max_depth},"
        f"min_samples_split:{args.min_samples_split},"
        f"min_samples_leaf:{args.min_samples_leaf}",
        flush=True,
    )
    print(f"rmse={bundle.rmse:.2f}", flush=True)
    print(f"mae={bundle.mae:.2f}", flush=True)
    time.sleep(5)


if __name__ == "__main__":
    main()
