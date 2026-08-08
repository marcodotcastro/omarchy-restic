# Omarchy Restic

Scripts para fazer uma migração segura do Linux Mint para o Omarchy usando um repositório Restic criptografado em um HD externo.

O repositório GitHub contém somente os scripts e esta documentação. Ele não contém senha, chave privada, projetos ou dados do backup.

## O que é salvo

O backup inclui:

- todo o `$HOME`;
- `RubymineProjects`, histórico Git e worktrees;
- documentos, Obsidian e configurações de usuário;
- `.env`, `.ssh`, `.gnupg`, configurações do Git e ferramentas;
- inventário de pacotes, versões, gems e pacotes npm;
- inventário Docker e arquivos dos volumes Docker nomeados, quando possível.

São excluídos somente conteúdos regeneráveis: caches, Lixeira, `node_modules`, `vendor/bundle`, `.bundle`, `tmp`, `log`, `coverage` e `.terraform` dentro do `$HOME`.

O conteúdo do repositório Restic é criptografado. A perda da senha torna o backup irrecuperável. Nunca coloque a senha em um commit, README, script ou variável persistente.

## Requisitos

- Linux com Bash;
- Restic 0.12 ou mais recente;
- `rsync` para restauração;
- HD externo montado;
- Docker opcional para inventário e volumes.

O caminho padrão do repositório é:

```text
/media/$USER/Backup/omarchy-restic-v2
```

Se o sistema montar o HD em outro caminho, defina `RESTIC_REPOSITORY` antes de executar o script.

## 1. Preparar o backup no Linux Mint

Clone este repositório ou use os scripts já copiados para o HD externo:

```bash
git clone git@github.com:marcodotcastro/omarchy-restic.git "$HOME/omarchy-restic"
cd "$HOME/omarchy-restic"
chmod 700 omarchy-restic-backup omarchy-restic-restore
```

Para HTTPS, use:

```bash
git clone https://github.com/marcodotcastro/omarchy-restic.git "$HOME/omarchy-restic"
```

Confirme que o HD está montado e selecione o repositório v2:

```bash
export BACKUP_MOUNT="/media/$USER/Backup"
export RESTIC_REPOSITORY="$BACKUP_MOUNT/omarchy-restic-v2"
findmnt -T "$RESTIC_REPOSITORY"
restic snapshots
```

Antes de fazer backup de bancos em Docker, pare os containers que escrevem dados, quando possível. O arquivamento de volume é somente leitura, mas não substitui um `pg_dump` transacional.

Execute o backup completo com um único comando:

```bash
./omarchy-restic-backup
```

O script:

1. pede a senha uma única vez;
2. cria um inventário do sistema e das ferramentas;
3. arquiva volumes Docker nomeados, quando o Docker estiver disponível;
4. cria um snapshot com a tag `omarchy-migration`;
5. executa `restic check`.

Ao final, confirme que apareceu um snapshot e `no errors were found`:

```bash
restic snapshots --tag omarchy-migration --latest 1
restic check
```

Se não quiser arquivar volumes Docker nesta execução:

```bash
./omarchy-restic-backup --no-docker-volumes
```

## 2. Guardar os scripts fora do disco que será apagado

Faça uma cópia dos scripts para o HD externo antes de instalar o Omarchy:

```bash
install -d -m 700 "$BACKUP_MOUNT/omarchy-migration-tools"
install -m 700 omarchy-restic-backup "$BACKUP_MOUNT/omarchy-migration-tools/omarchy-restic-backup"
install -m 700 omarchy-restic-restore "$BACKUP_MOUNT/omarchy-migration-tools/omarchy-restic-restore"
```

Na instalação do Omarchy, selecione somente o disco interno correto. Não formate o HD externo que contém `Backup`.

## 3. Restaurar depois de instalar o Omarchy

Monte o HD externo. O caminho pode ser `/media/$USER/Backup` ou `/run/media/$USER/Backup`.

Instale as dependências mínimas:

```bash
sudo pacman -S --needed restic rsync
```

Defina o caminho real do repositório:

```bash
export BACKUP_MOUNT="/run/media/$USER/Backup"
export RESTIC_REPOSITORY="$BACKUP_MOUNT/omarchy-restic-v2"
```

Veja o plano sem alterar arquivos:

```bash
"$BACKUP_MOUNT/omarchy-migration-tools/omarchy-restic-restore" --plan
```

Faça a restauração completa, com confirmação interativa:

```bash
"$BACKUP_MOUNT/omarchy-migration-tools/omarchy-restic-restore" --full
```

O `--full` restaura o `$HOME`, oferece a instalação das ferramentas-base e recupera volumes Docker ausentes. Ele não usa `--delete`; os arquivos existentes que forem sobrescritos são preservados em:

```text
~/.omarchy-restic-pre-restore-<data>
```

Depois de revisar o plano, é possível executar sem perguntas:

```bash
"$BACKUP_MOUNT/omarchy-migration-tools/omarchy-restic-restore" --full --yes
```

Volumes Docker já existentes são preservados. A substituição explícita é destrutiva e exige:

```bash
"$BACKUP_MOUNT/omarchy-migration-tools/omarchy-restic-restore" --full --replace-docker-volumes
```

## 4. Depois da restauração

O script restaura os projetos e seus lockfiles, mas não executa comandos arbitrários dentro dos projetos. Reinstale as dependências de cada projeto conforme necessário, por exemplo `bundle install` para Rails e `npm install` ou `pnpm install` para projetos Node.

Valide os projetos principais:

```bash
find "$HOME/RubymineProjects" -maxdepth 2 -type d -name .git -print
restic snapshots --tag omarchy-migration --latest 1
```

## Opções úteis

```bash
omarchy-restic-backup --help
omarchy-restic-restore --help
omarchy-restic-restore --plan
```

Variáveis aceitas:

- `RESTIC_REPOSITORY`: caminho do repositório;
- `OMARCHY_RESTIC_MOUNT`: ponto de montagem do HD;
- `OMARCHY_RESTIC_WORKDIR`: área temporária da restauração;
- `OMARCHY_RESTIC_DOCKER_IMAGE`: imagem usada para arquivar/restaurar volumes Docker.

## Problemas comuns

### `wrong password or no key found`

Não inicialize o repositório novamente e não apague dados. Confirme que está usando `/omarchy-restic-v2` e tente somente a senha criada para esse repositório.

### Repositório não encontrado

O HD provavelmente não está montado ou recebeu outro caminho. Confira:

```bash
lsblk -f
findmnt
```

### Volume Docker ignorado

O script registra volumes que não puderam ser arquivados no manifest. Verifique o daemon Docker, espaço livre e a mensagem exibida pelo backup antes de instalar o Omarchy.
