.PHONY: build-lambda
build-lambda:
	zip -rj email-lambda.zip email-lambda/*

.PHONY: update-lambda
update-lambda: build-lambda
	aws lambda update-function-code --function-name email-forwarder-lambda --zip-file fileb://email-lambda.zip
