.PHONY: setup init plan deploy destroy test lint clean build-image

INFRA_DIR := infra
APP_DIR := app

setup:
	bash setup.sh

init:
	cd $(INFRA_DIR) && terraform init

plan:
	cd $(INFRA_DIR) && terraform plan

deploy:
	cd $(INFRA_DIR) && terraform apply -auto-approve

destroy:
	cd $(INFRA_DIR) && terraform destroy -auto-approve

build-image:
	cd $(APP_DIR) && bash build_and_push.sh

test:
	python -m pytest tests/ -v

lint:
	python -m py_compile functions/agent_factory/handler.py
	python -m py_compile functions/test_runner/handler.py
	python -m py_compile functions/per_agent_evaluator/handler.py
	python -m py_compile functions/per_agent_evaluator/rubrics.py
	python -m py_compile functions/e2e_evaluator/handler.py
	python -m py_compile functions/report_generator/handler.py
	python -m py_compile functions/promoter/handler.py
	python -m py_compile app/supervisor.py
	cd $(INFRA_DIR) && terraform validate

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.pyc" -delete 2>/dev/null || true
	rm -rf $(INFRA_DIR)/.packages/

trigger:
	@BUCKET=$$(cd $(INFRA_DIR) && terraform output -raw bucket_name) && \
	aws s3 cp configs/sample-config.json "s3://$$BUCKET/config/regression-config.json"
	@echo "Pipeline triggered. Check Step Functions console for execution."
