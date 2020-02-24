# How to

1. Build docker image:

```bash
docker build -t xxx .
```

2. run it interactively and mount the local folder:

```bash
docker run -it -v /path_to_code:/tf xxx
```

3. (**This and the followings steps would be inside the container**) Perform setup:

```bash
cd /tf
az login
terraform init
```

4. Run terraform to create resources:

```
terraform apply -auto-approve
```

5. Run terraform to clean up:

```
terraform destroy -auto-approve
```
