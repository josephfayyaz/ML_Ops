import argparse
import time

from mlops_iris.model import train_model


def main() -> None:
    parser = argparse.ArgumentParser(description="Katib objective for the iris demo")
    parser.add_argument("--n-estimators", type=int, required=True)
    parser.add_argument("--max-depth", type=int, required=True)
    parser.add_argument("--min-samples-split", type=int, required=True)
    args = parser.parse_args()

    bundle = train_model(
        n_estimators=args.n_estimators,
        max_depth=args.max_depth,
        min_samples_split=args.min_samples_split,
    )

    print(
        "trial="
        f"n_estimators:{args.n_estimators},"
        f"max_depth:{args.max_depth},"
        f"min_samples_split:{args.min_samples_split}",
        flush=True,
    )
    print(f"accuracy={bundle.accuracy:.4f}", flush=True)
    print(f"loss={1.0 - bundle.accuracy:.4f}", flush=True)
    # Keep the process alive briefly so Katib's metrics collector sidecar can
    # persist the final metrics before the Job exits.
    time.sleep(5)


if __name__ == "__main__":
    main()
