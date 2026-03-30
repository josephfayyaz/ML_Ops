FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    MLOPS_HOUSE_PRICES_DATA=/app/data/house-prices/ames_housing_selected.csv

WORKDIR /app

COPY images/mlops-demo/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY apps/iris-service/mlops_iris ./mlops_iris
COPY apps/house-prices/mlops_house_prices ./mlops_house_prices
COPY apps/house-prices/data ./data/house-prices
COPY apps/results-dashboard/mlops_results_dashboard ./mlops_results_dashboard

EXPOSE 8000

CMD ["python", "-m", "mlops_iris.serve"]
