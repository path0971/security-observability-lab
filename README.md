# security-observability-lab

AWS에 EKS 기반 샘플 API와 보안 관측 파이프라인(CloudTrail, GuardDuty, Security Hub, CloudWatch Logs → Wazuh)을 Terraform으로 구성하는 실습 프로젝트입니다.

## 구성

| 경로 | 내용 |
| --- | --- |
| `infra/bootstrap` | Terraform 상태 파일용 S3 버킷 |
| `infra/network` | VPC, public/app/db 서브넷, 라우팅 테이블 |
| `infra/management` | NAT Gateway, SSM 전용 관리 EC2 |
| `infra/eks` | 프라이빗 EKS 클러스터, 노드 그룹 |
| `infra/ecr` | 앱 이미지 저장소 |
| `infra/ingress` | AWS Load Balancer Controller용 IRSA 역할 |
| `infra/rds` | MySQL 8.4 RDS (TLS 강제) |
| `infra/logging` | CloudTrail, 앱 로그 그룹, Wazuh 읽기 전용 IAM 사용자 |
| `infra/security` | GuardDuty, Security Hub, Findings → Firehose → S3 → SQS |
| `app/` | Flask API (JSON 구조화 로그) |
| `k8s/` | API Deployment/Service 매니페스트 |

## 사전 요구사항

- Terraform `>= 1.10`
- AWS CLI v2와 배포 대상 계정의 프로필 (`aws configure sso` 등)
- Docker, kubectl

## 설정

계정별 값은 저장소에 포함되어 있지 않습니다. 아래 예시 파일을 복사해서 본인 값을 넣으세요. 복사한 파일은 `.gitignore`에 등록되어 있어 커밋되지 않습니다.

```bash
# 1) 공통 백엔드 설정
cp infra/backend.hcl.example infra/backend.hcl

# 2) 스택별 변수
for d in infra/*/; do cp "$d/terraform.tfvars.example" "$d/terraform.tfvars"; done
```

| 값 | 설명 |
| --- | --- |
| `<AWS_ACCOUNT_ID>` | 12자리 AWS 계정 ID |
| `<AWS_PROFILE>` | AWS CLI 프로필 이름 |

리전은 `ap-northeast-2`로 고정되어 있습니다. S3 버킷 이름은 `security-lab-<용도>-<계정ID>-ap-northeast-2` 형식으로 만들어집니다.

`infra/rds/terraform.tfvars`에는 network/eks 스택을 적용한 뒤 확인한 `vpc_id`, `eks_security_group_id`(EKS 클러스터 보안 그룹), `db_subnet_ids`도 넣어야 합니다.

## 배포 순서

스택끼리 원격 상태와 데이터 소스로 서로 참조하므로 아래 순서대로 적용합니다.

1. **bootstrap**: 상태 버킷이 아직 없으므로 처음 한 번은 로컬 상태로 생성합니다.
   ```bash
   cd infra/bootstrap
   mv backend.tf backend.tf.off        # 임시로 원격 백엔드 비활성화
   terraform init && terraform apply
   mv backend.tf.off backend.tf
   terraform init -backend-config=../backend.hcl -migrate-state
   ```
2. 나머지 스택은 각 디렉터리에서 다음 순서로 실행합니다.
   ```bash
   terraform init -backend-config=../backend.hcl
   terraform apply
   ```
   `network` → `management` → `eks` → `ecr` → `ingress` → `rds` → `logging` → `security`

## 앱 빌드 및 배포

```bash
ACCOUNT_ID=<AWS_ACCOUNT_ID>; REGION=ap-northeast-2
REPO=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/security-lab-api

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
docker build -t $REPO:0.2.0 app
docker push $REPO:0.2.0
```

`k8s/security-lab-api.yaml`을 `k8s/security-lab-api.local.yaml`로 복사하고, `image`의 플레이스홀더를 push한 이미지 digest로 바꿔서 배포합니다. `*.local.yaml` 파일은 커밋되지 않습니다.

```bash
kubectl create namespace security-lab
kubectl apply -f k8s/security-lab-api.local.yaml
```

EKS API 엔드포인트가 프라이빗이므로 `kubectl`은 SSM으로 접속한 관리 EC2에서 실행합니다.

### 앱 환경변수

| 변수 | 설명 |
| --- | --- |
| `DB_HOST`, `DB_PORT`, `DB_NAME` | RDS 접속 정보 (`infra/rds` outputs) |
| `DB_USER`, `DB_PASSWORD` | DB 계정 (마스터 비밀번호는 Secrets Manager에서 관리) |
| `DB_SSL_CA` | RDS CA 번들 경로 |

DB 변수를 설정하지 않아도 앱은 기동되며, 이때 `/api/db`는 503을 반환합니다.

## 정리

RDS와 상태 버킷에는 `prevent_destroy`와 `deletion_protection`이 걸려 있으므로, 삭제하려면 해당 설정을 먼저 해제해야 합니다.
