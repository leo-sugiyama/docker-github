SHELL           := powershell.exe
.SHELLFLAGS     := -NoProfile -Command

MAKE            := make
DOCKER_IMAGE    := busybox alpine

PROJECT         := $(shell Split-Path $$pwd -Leaf)
SERVICES        := $(shell & docker-compose config --services)
VOLUMES         := $(shell & docker-compose config --volumes)

BACKUP_BASE     := backup
BACKUP_DIR      := $(shell "$(BACKUP_BASE)/$$(Get-Date -Format yyyyMMdd-HHmmss)")
RESTORE_POINT   := $(lastword $(sort $(wildcard $(BACKUP_BASE)/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9])))
ROTATE_COUNT    := 2

.PHONY: all
all: ;

################################################################################
# コンテナ作成/削除/起動/停止
################################################################################
.PHONY: init
init:
	& docker-compose --profile once up --detach

# "docker compose up" なら gitlab が certs に depends_on していても起動できた
.PHONY: up
up:
	& docker compose up --detach

.PHONY: down
down:
	& docker-compose down

.PHONY: clean
clean:
	& docker-compose --profile once down --volumes

.PHONY: start
start:
	& docker-compose start

.PHONY: stop
stop:
	& docker-compose stop

.PHONY: restart
restart:
	& docker-compose restart

################################################################################
# アップグレード (バージョンアップ)
################################################################################
.PHONY: upgrade
upgrade:
	$(MAKE) backup-gitlab
	$(MAKE) down
	$(MAKE) backup-raw
	& docker-compose pull
	$(MAKE) up
	# & docker image prune

################################################################################
# volume データ削除
################################################################################
.PHONY: reset-data
reset-data:
	$(foreach volume, $(filter-out %-certs,$(VOLUMES)), & docker run --rm --volume $(PROJECT)_$(volume):/volume busybox /bin/ash -c 'rm -rvf /volume/*';)

.PHONY: reset-all
reset-all:
	$(foreach volume, $(VOLUMES), & docker run --rm --volume $(PROJECT)_$(volume):/volume busybox /bin/ash -c 'rm -rvf /volume/*';)

################################################################################
# バックアップ/リストア
################################################################################
.PHONY: backup
backup:
	$(MAKE) backup-gitlab
	$(MAKE) stop
	$(MAKE) backup-raw
	$(MAKE) rotate
	$(MAKE) start

.PHONY: backup-gitlab
backup-gitlab:
	& docker-compose exec gitlab gitlab-backup create

.PHONY: backup-raw
backup-raw:
	if (!(Test-Path("$$pwd/$(BACKUP_BASE)"))) { mkdir "$$pwd/$(BACKUP_BASE)" -Force | Out-Null }
	& docker run -it --rm $(foreach volume, $(VOLUMES), --volume $(PROJECT)_$(volume):/$(volume):ro) --volume "$$pwd/$(BACKUP_BASE):/$(BACKUP_BASE)" busybox /bin/ash -c 'mkdir -p /$(BACKUP_DIR) && $(foreach volume, $(VOLUMES), tar czvf /$(BACKUP_DIR)/$(volume).tar.gz /$(volume) &&) true'

.PHONY: restore-raw
restore-raw:
	$(if $(RESTORE_POINT), , $(error RESTORE_POINT is empty.))
	$(if $(wildcard $(RESTORE_POINT)/*), , $(error RESTORE_POINT is empty.))
	& docker run -it --rm $(foreach volume, $(VOLUMES), --volume $(PROJECT)_$(volume):/$(volume)) --volume "$$pwd/$(BACKUP_BASE):/$(BACKUP_BASE):ro" busybox /bin/ash -c '$(foreach volume, $(VOLUMES), rm -rf /$(volume)/* && tar xvf /$(RESTORE_POINT)/$(volume).tar.gz -C /$(volume) --strip=1 &&) true'

.PHONY: rotate
rotate:
	ls $(BACKUP_BASE) -Directory | where { $$_.Name -match "^\d{8}-\d{6}$$" } | sort -Descending | select -Skip $(ROTATE_COUNT) | rm -Recurse -Force -Verbose 4>&1

################################################################################
# コンテナ作業/ボリューム作業
# bash を優先して shell 起動
################################################################################
# 全ボリュームをマウントした docker イメージ 起動
.PHONY: $(DOCKER_IMAGE)
$(DOCKER_IMAGE):
	& docker run -it --rm $(foreach volume, $(VOLUMES), --volume $(PROJECT)_$(volume):/$(volume)) $@ /bin/sh -c '/bin/bash || /bin/sh'

# docker-compose.yml のコンテナに shell で入る
.PHONY: $(SERVICES)
$(SERVICES):
	& docker-compose exec $@ /bin/sh -c '/bin/bash || /bin/sh'
