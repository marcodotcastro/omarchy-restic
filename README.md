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
- inventário e metadados Docker, sem o conteúdo dos volumes.

São excluídos somente conteúdos regeneráveis: caches, Lixeira, `node_modules`, `vendor/bundle`, `.bundle`, `tmp`, `log`, `coverage` e `.terraform` dentro do `$HOME`.

O conteúdo do repositório Restic é criptografado. A perda da senha torna o backup irrecuperável. Nunca coloque a senha em um commit, README, script ou variável persistente.

## Requisitos

- Linux com Bash;
- Restic 0.12 ou mais recente;
- `rsync` para restauração;
- HD externo montado;
- Docker opcional para inventário.

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
chmod 700 omarchy-restic-backup omarchy-restic-restore omarchy-restic-verify omarchy-restic-app-test
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

Execute o backup completo com um único comando:

```bash
./omarchy-restic-backup
```

O script:

1. pede a senha uma única vez;
2. cria um inventário do sistema e das ferramentas;
3. registra containers, imagens, redes, volumes e projetos Compose Docker;
4. cria um snapshot com a tag `omarchy-migration`;
5. executa `restic check`.

Ao final, confirme que apareceu um snapshot e `no errors were found`:

```bash
restic snapshots --tag omarchy-migration --latest 1
restic check
```

## 2. Validar backup e restore antes de instalar

Execute a validação completa antes de apagar o disco interno:

```bash
./omarchy-restic-verify
```

O script exige um snapshot com a tag `omarchy-migration`, executa `restic check --read-data` e restaura o snapshot inteiro para uma pasta temporária no HD externo usando `--verify`. Ele também confirma o manifest e, quando `RubymineProjects` existe no HOME atual, confirma que esse diretório foi restaurado. O `$HOME` atual nunca é alterado.

Essa etapa pode demorar e precisa de espaço livre suficiente para uma cópia temporária do backup. A pasta temporária é removida automaticamente quando tudo passa; em caso de erro, o caminho é preservado para diagnóstico. Para mantê-la mesmo após sucesso:

```bash
./omarchy-restic-verify --keep-restore
```

Se quiser escolher outra área temporária já existente:

```bash
export OMARCHY_RESTIC_VERIFY_WORKDIR="/caminho/com/espaco"
./omarchy-restic-verify
```

## 3. Ensaiar remoção e restauração de aplicativos

O script dedicado permite escolher exatamente três aplicativos do catálogo
`omarchy-restic-apps.conf` e testar a sequência completa sem remover nada
automaticamente:

```bash
export RESTIC_REPOSITORY="/media/$USER/Backup/omarchy-restic-v2"

./omarchy-restic-app-test capture \
  --app rubymine \
  --app jetbrains-toolbox \
  --app obsidian
./omarchy-restic-app-test verify-capture
```

Somente depois de `capture` e `verify-capture` terminarem com sucesso, feche e
desinstale manualmente os três aplicativos. Em seguida, execute:

```bash
./omarchy-restic-app-test assert-removed
./omarchy-restic-app-test restore
./omarchy-restic-app-test validate
```

O teste não remove aplicativos automaticamente e não usa `--delete`. O
`restore` copia apenas os caminhos de usuário definidos no catálogo e guarda
arquivos sobrescritos em:

```text
~/.omarchy-restic-app-test-pre-restore-<data>-<pid>
```

RubyMine, Toolbox e Obsidian precisam estar instalados no momento do `capture`
para que a remoção e a restauração dos executáveis sejam realmente testadas.
As pastas `~/.config/JetBrains/RubyMine*` comprovam o estado de configuração,
mas não substituem um executável ausente. O catálogo usa o caminho real do
Toolbox (`.../apps/rubymine*`) e não exige uma segunda instalação em `/opt`.

Se um catálogo personalizado incluir instalação em `/opt` ou `/usr/share`,
esses arquivos aparecem como `STAGED ONLY`: são verificados na área temporária,
mas não são copiados com `sudo` automaticamente. Para este ensaio, Obsidian foi
escolhido como terceiro aplicativo porque seu AppImage, symlink, launcher e
configuração ficam no HOME e podem ser restaurados sem privilégios. O catálogo
também inclui `Documents/Obsidian Vault`, preservando o repositório Git e seu
remote sem exibir a URL. O terceiro aplicativo pode ser trocado por outro ID
existente no catálogo.

O snapshot deste ensaio usa a tag `omarchy-app-test` e não substitui o
snapshot principal `omarchy-migration`. O conteúdo dos volumes Docker
continua fora de ambos os backups.

## 4. Guardar os scripts fora do disco que será apagado

Faça uma cópia dos scripts para o HD externo antes de instalar o Omarchy:

```bash
install -d -m 700 "$BACKUP_MOUNT/omarchy-migration-tools"
install -m 700 omarchy-restic-backup "$BACKUP_MOUNT/omarchy-migration-tools/omarchy-restic-backup"
install -m 700 omarchy-restic-restore "$BACKUP_MOUNT/omarchy-migration-tools/omarchy-restic-restore"
install -m 700 omarchy-restic-verify "$BACKUP_MOUNT/omarchy-migration-tools/omarchy-restic-verify"
install -m 700 omarchy-restic-app-test "$BACKUP_MOUNT/omarchy-migration-tools/omarchy-restic-app-test"
install -m 644 omarchy-restic-apps.conf "$BACKUP_MOUNT/omarchy-migration-tools/omarchy-restic-apps.conf"
```

Na instalação do Omarchy, selecione somente o disco interno correto. Não formate o HD externo que contém `Backup`.

## 5. Restaurar depois de instalar o Omarchy

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

O `--full` restaura o `$HOME` e oferece a instalação das ferramentas-base. O inventário Docker é restaurado como parte dos arquivos de configuração, mas o conteúdo dos volumes não faz parte deste backup. O script não usa `--delete`; os arquivos existentes que forem sobrescritos são preservados em:

```text
~/.omarchy-restic-pre-restore-<data>
```

Depois de revisar o plano, é possível executar sem perguntas:

```bash
"$BACKUP_MOUNT/omarchy-migration-tools/omarchy-restic-restore" --full --yes
```

## 6. Depois da restauração

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
omarchy-restic-verify --help
omarchy-restic-app-test --help
```

Variáveis aceitas:

- `RESTIC_REPOSITORY`: caminho do repositório;
- `OMARCHY_RESTIC_MOUNT`: ponto de montagem do HD;
- `OMARCHY_RESTIC_WORKDIR`: área temporária da restauração;
- `OMARCHY_RESTIC_VERIFY_WORKDIR`: área temporária específica da validação completa.

## Problemas comuns

### `wrong password or no key found`

Não inicialize o repositório novamente e não apague dados. Confirme que está usando `/omarchy-restic-v2` e tente somente a senha criada para esse repositório.

### Repositório não encontrado

O HD provavelmente não está montado ou recebeu outro caminho. Confira:

```bash
lsblk -f
findmnt
```

### Dados Docker

O conteúdo dos volumes Docker não é salvo. Os arquivos Compose, o inventário de containers e os nomes/configurações dos volumes são preservados para recriação do ambiente; bancos locais devem ser recriados ou exportados separadamente se forem necessários.
