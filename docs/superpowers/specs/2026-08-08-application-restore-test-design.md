# Design: teste reversível de aplicativos na migração Mint → Omarchy

Status: FINAL
Data: 2026-08-08

## Objetivo

Permitir testar, antes da migração definitiva, se três aplicativos escolhidos
pelo usuário podem ser removidos manualmente e ter seus dados de usuário
restaurados corretamente pelo Restic.

O teste deve separar explicitamente:

- estado do usuário: configurações, histórico, tarefas, plugins, launchers e
  arquivos instalados dentro do HOME;
- instalação do executável: pacote, AppImage, Toolbox ou instalação em
  `/opt`, que só será considerada recuperável quando houver um instalador ou
  uma receita reproduzível preservada.

O teste não deve apagar arquivos automaticamente, não deve usar `--delete` e
não deve alterar volumes Docker.

## Evidência atual

- `~/.config/JetBrains/RubyMine2025.1`, `RubyMine2025.2`, `RubyMine2025.3` e
  `RubyMine2026.1` contêm configurações, tarefas, projetos recentes, plugins e
  arquivos de estado.
- `~/.local/share/JetBrains/Toolbox` contém apenas arquivos de estado; não há
  atualmente o executável do Toolbox nem diretórios de aplicativos Toolbox.
- Não foi encontrado executável `rubymine` ou `jetbrains-toolbox` no HOME,
  `/opt` ou nos caminhos de binários pesquisados.
- Consequentemente, o primeiro teste real de RubyMine/Toolbox exigirá que o
  aplicativo esteja instalado e que seja possível identificar seu método de
  instalação antes da captura.

## Abordagens consideradas

### A. Script dedicado com snapshot próprio — recomendado

Criar `omarchy-restic-app-test` com um catálogo de aplicativos e fases
explícitas (`capture`, `verify-capture`, `assert-removed`, `restore` e
`validate`). A captura cria um snapshot adicional com a tag
`omarchy-app-test`, contendo somente os caminhos selecionados e um manifest
de metadados.

Vantagens: isola o teste do restore completo, permite repetir o ensaio com
três aplicativos diferentes e deixa claro o que será restaurado. O risco de
uma restauração experimental afetar o snapshot principal é menor.

### B. Adicionar um modo de teste ao restore completo

Estender `omarchy-restic-restore` para receber três aplicativos e usar o
snapshot `omarchy-migration`.

Vantagem: menos um executável para distribuir. Desvantagens: mistura uma
operação experimental com o restore de produção, torna o restore mais difícil
de revisar e não registra de forma isolada quais caminhos pertenciam ao teste.

### C. Comandos manuais fora dos scripts

Usar `restic backup`, `restic restore`, `sha256sum` e `rsync` manualmente para
cada aplicativo.

Vantagem: implementação imediata. Desvantagens: não é repetível, facilita
esquecer arquivos ocultos e não produz um procedimento confiável para a
migração real.

## Desenho recomendado

### Catálogo de aplicativos

O script terá um catálogo versionado e editável, separado da lista geral de
aplicativos instalados. Cada entrada terá:

- identificador usado no comando, como `rubymine` ou `jetbrains-toolbox`;
- nome legível e método de instalação esperado;
- caminhos de usuário a preservar;
- caminhos de instalação a verificar, sem copiá-los automaticamente para
  locais de sistema;
- comando ou launcher esperado;
- exclusões explícitas para caches e logs regeneráveis;
- indicação se um instalador local é obrigatório para validar o executável.

RubyMine e JetBrains Toolbox serão entradas iniciais. O terceiro aplicativo
será escolhido no comando, sem ficar embutido como uma decisão permanente no
script.

### Fase `capture`

1. Exigir exatamente três identificadores válidos.
2. Exigir que os aplicativos estejam fechados para evitar capturar bancos de
   estado em alteração.
3. Exigir que os caminhos obrigatórios de instalação existam quando a entrada
   exigir um teste completo do executável; caso contrário, falhar com uma
   mensagem explicando que apenas a configuração não comprova reinstalação.
4. Registrar, sem imprimir conteúdo privado, tipo, modo, tamanho, destino de
   symlink e SHA-256 dos arquivos preserváveis.
5. Criar um snapshot Restic adicional com a tag `omarchy-app-test`, incluindo
   os caminhos selecionados dentro do HOME, o manifest e, quando fornecido,
   o instalador local.

O snapshot principal `omarchy-migration` continua sendo obrigatório para a
migração completa. O snapshot de teste não o substitui.

### Fase `verify-capture`

Antes da desinstalação manual, o script restaurará o snapshot de teste em uma
área temporária separada, usando `restic restore --verify`, e comparará o
manifest restaurado com a captura original. O HOME atual nunca será alterado.

Essa etapa prova que os três conjuntos de dados foram realmente gravados e
podem ser lidos antes de qualquer remoção.

### Fase `assert-removed`

Depois que o usuário desinstalar manualmente os aplicativos, o script
verificará os artefatos de instalação definidos pelo catálogo:

- comando esperado ausente ou não executável;
- launcher ou diretório de instalação ausente, quando aplicável;
- arquivos de configuração preserváveis podem continuar presentes, pois a
  desinstalação de aplicativos Linux frequentemente não os remove.

Essa fase não apaga configurações remanescentes e não considera a ausência de
um executável como prova de que a captura foi feita corretamente; a captura
já terá falhado se o teste completo exigia um executável inexistente.

### Fase `restore`

1. Restaurar o snapshot `omarchy-app-test` para uma área temporária com
   verificação Restic.
2. Exibir um plano contendo apenas os caminhos dos três aplicativos.
3. Pedir confirmação explícita.
4. Copiar somente os caminhos de usuário para o HOME com `rsync` sem
   `--delete`.
5. Preservar arquivos que forem sobrescritos em
   `~/.omarchy-restic-app-test-pre-restore-<data>`.
6. Deixar instaladores e arquivos de sistema em uma área de staging para
   inspeção; a cópia para `/opt` ou `/usr/share` exigirá uma ação manual
   explícita e privilegiada, caso seja necessária.

O restore não executará scripts de terceiros, não instalará pacotes sem uma
opção explícita e não copiará dados para fora dos caminhos aprovados pelo
catálogo.

### Fase `validate`

Comparar o estado após o restore com o manifest capturado:

- arquivos obrigatórios presentes;
- SHA-256 igual para arquivos regulares;
- tipo e destino iguais para symlinks;
- modo de permissão preservado, sem exigir o mesmo UID/GID do Mint;
- launcher restaurado com destino existente, quando aplicável;
- comando executável ou caminho instalado presente quando o instalador foi
  preservado e restaurado.

O relatório exibirá somente `PASS`, `FAIL` e caminhos, nunca conteúdo de
chaves, tokens, cookies ou arquivos de memória.

## Segurança e limites

- O snapshot continua criptografado pela senha do repositório.
- O teste não valida credenciais fazendo login nem imprime segredos.
- RubyMine/Toolbox podem possuir tokens, chaves de licença ou históricos em
  arquivos de configuração; eles serão protegidos pelo Restic, mas o usuário
  deve tratar o repositório como material sensível.
- Um snapshot Restic consegue restaurar arquivos, mas não garante que um
  pacote externo, AppImage ou instalação em `/opt` seja reinstalável sem o
  instalador correspondente.
- O conteúdo dos volumes Docker permanece fora do backup e fora deste teste.

## Critérios de sucesso

O teste só será considerado aprovado quando:

1. os três aplicativos forem capturados com manifest completo;
2. `verify-capture` terminar sem erro e com `restic restore --verify`;
3. `assert-removed` confirmar a remoção manual dos artefatos selecionados;
4. `restore` copiar apenas os caminhos aprovados;
5. `validate` confirmar hashes, tipos, permissões e launchers esperados;
6. qualquer executável não restaurável for reportado como falha explícita, e
   não como sucesso baseado apenas na presença da configuração.

## Decisões

- O usuário aprovou separar a validação de dados/configuração da validação de
  reinstalação do executável.
- RubyMine e JetBrains Toolbox serão candidatos iniciais do teste.
- O terceiro aplicativo será selecionável pelo comando.
- A primeira implementação usará um script dedicado com snapshot próprio,
  para não misturar teste destrutivo com o restore completo.
- O teste não removerá automaticamente aplicativos nem usará `--delete`.
- O Redis server e os itens ambíguos permanecem fora do conjunto `REMOVER`,
  conforme a decisão anterior do usuário.
