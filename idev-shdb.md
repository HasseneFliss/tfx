# 📘 How to Initialize Any Project in iDev (Stateless + Shared DB)

> **الهدف من هذا الـ README**
> نفسّرلك بالضبط كيفاش تخدم iDev، شنّا هو DB، شنّا هو shared-db، وكيفاش تبدأ أي project جديد **بلا confusion**.

---

## 1️⃣ شنّا هو iDev؟ (Concept لازم يكون واضح)

iDev environment **ما هوش namespace واحد**، بل يتكوّن من **زوز namespaces يخدمو مع بعضهم**:

### 🔹 Stateless namespaces

فيهم applications فقط:

* Deployment
* Service
* Ingress
* PDB

**ما فيهمش state**
**ما فيهمش DB**

أمثلة:

* `mfx-every`
* `payment`
* `orders`

---

### 🔹 shared-db namespace

هذا namespace خاص **بالحاجات الـ stateful فقط**:

* Databases (MySQL, PostgreSQL…)
* StatefulSets
* PVC
* Backups / snapshots / migrations

اسمو ديما:

```
shared-db
```

👉 Application **ما يلزمهاش** تعمل DB داخل namespace متاعها
👉 أي DB **لازم تتخلق في shared-db**

---

## 2️⃣ Big Picture Architecture

```
┌──────────────────────────┐
│  mfx-every (stateless)   │
│                          │
│  App ──► ExternalName ───┼────► MySQL (shared-db)
│                          │
└──────────────────────────┘
```

* App تعيش في `mfx-every`
* DB تعيش في `shared-db`
* الربط يصير عبر **ExternalName Service**

---

## 3️⃣ Folder Structure (STANDARD)

كل service عندها **زوز folders**:

* app
* db (definition فقط)

```
services/
├── mfx-every/
│   ├── base/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   ├── pdb.yaml
│   │   └── kustomization.yaml
│   ├── idev-service-v1.0.0.yaml
│   └── kustomization.yaml
│
├── mfx-every-db/
│   └── base/
│       ├── kustomization.yaml
│       ├── statefulset.yaml
│       ├── service.yaml
│       ├── persistent-volume-claim.yaml
│       └── files/
│           ├── my.cnf
│           └── setup.sql
│
└── shared-db-external-name/
    └── base/
        └── service.yaml
```

⚠️ وجود `mfx-every-db` **ما يعنيش** DB تتنصّب تلقائيًا

---

## 4️⃣ Step-by-Step: Create a New Project in iDev

نفترض service اسمها: `mfx-every`

---

### STEP 1️⃣ Define the Database (DB definition فقط)

📍 Path:

```
services/mfx-every-db/base/
```

#### `kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - statefulset.yaml
  - service.yaml
  - persistent-volume-claim.yaml

configMapGenerator:
  - name: mfx-every-db-mysql-my-cnf
    files:
      - files/my.cnf
  - name: mfx-every-db-mysql-setup-sql
    files:
      - files/setup.sql
```

#### `statefulset.yaml`

فيه:

* MySQL image
* volume mounts
* env vars
* certificates

👉 هذا يعرّف DB فقط
👉 **ما يركّبهاش**

---

### STEP 2️⃣ Install DB into shared-db namespace

📍 Path:

```
namespaces/shared-db/databases/mfx-every-db/kustomization.yaml
```

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../../../services/mfx-every-db
```

✔️ هذا هو **الـ step الوحيد** اللي يخلّي DB تتخلق فعليًا
✔️ MySQL + PVC + Service يمشيو لـ `shared-db`

---

### STEP 3️⃣ Expose DB via ExternalName

📍 Path:

```
services/shared-db-external-name/base/service.yaml
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mfx-every-db
spec:
  type: ExternalName
  externalName: mfx-every-db.shared-db.svc.cluster.local
  ports:
    - port: 3306
```

✔️ يسمح لأي namespace يستعمل:

```
mfx-every-db.<namespace>
```

---

### STEP 4️⃣ Consume DB from the App (stateless namespace)

📍 Namespace:

```
mfx-every
```

App env vars:

```
DB_HOST=mfx-every-db.mfx-every
DB_PORT=3306
```

❗ ما فماش MySQL هنا
❗ ما فماش PVC هنا
❗ غير consumption

---

### STEP 5️⃣ Declare shared dependency (Mandatory)

📍 Path:

```
services/mfx-every/idev-service-v1.0.0.yaml
```

```yaml
sharedDependencies:
  - source: shared-db
    service: mfx-every-db
```

✔️ ضروري لـ:

* ArgoCD
* dependency graph
* snapshots

---

## 6️⃣ What NOT to Do (أهم الغلطات)

❌ ما تعملش MySQL داخل `mfx-every`
❌ ما تعملش PVC خارج `shared-db`
❌ ما تعملش include متاع DB في `namespaces/mfx-every`
❌ ما تعملش ExternalName مكرّر

---

## 7️⃣ علاش architecture هكا؟

| Feature                 | Benefit                   |
| ----------------------- | ------------------------- |
| shared-db               | centralized DB management |
| Stateful isolation      | stability & backups       |
| ExternalName            | clean DNS access          |
| sharedDependencies      | ArgoCD awareness          |
| One DB, many namespaces | scalable                  |

---

## 8️⃣ Checklist Before PR ✅

* [ ] DB manifests في `services/<service>-db`
* [ ] DB مركّبة في `namespaces/shared-db/databases`
* [ ] ExternalName service مضاف
* [ ] App ما فيهاش MySQL
* [ ] sharedDependencies مضافة
* [ ] `kustomize build namespaces/mfx-every` ما يطلعش DB

---

## ✅ Final Summary (احفظها)

**In iDev:**

* Apps stateless
* Databases stateful
* Stateful يعيش في `shared-db`
* Apps تستهلك DB عبر ExternalName
* DB lifecycle مملوك للـ service
