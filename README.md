# Runners de CI da ATPlus

Imagens de ferramentas e configuração do pool ARC compartilhado pela organização.
As imagens contêm ferramentas públicas; os projetos permanecem em seus repositórios.

## Imagens

- `ghcr.io/atplus-digital/ci-runner`: runner oficial, Node 22, Python 3.12,
  Bun 1.4.0, compilador, bibliotecas Electron, ffmpeg, PowerShell, gh e Compose.
  Node/Python também ficam no tool cache das actions oficiais.
- `ghcr.io/atplus-digital/ci-browser`: acrescenta Chromium para Playwright 1.62.1
  (portal) e 1.61.1 (Vision), com smoke de launch das duas versões.
- `ghcr.io/atplus-digital/ci-linux-tools`: Ubuntu 24.04 com compilador,
  Chrome e bubblewrap 0.11.0 para os containers isolados do ATP Work.

PRs constroem e executam smoke real em runners hospedados do GitHub.
Somente `main` publica tags `sha-<commit completo>`, após os smokes.
Os builds exportam cache BuildKit para tags `buildcache` no GHCR.
Consumidores usam digest imutável; navegador e lockfile precisam corresponder.
Reconstruir em alterações de Dockerfile ou por dispatch para atualizar ferramentas.

## Pool

`cluster/pool.json` define 24 runners, dois disponíveis quando ocioso,
requests/limits de runner e Docker-in-Docker e distribuição por worker.
Há cinco workers de 8 vCPU/16 GiB. O teto parte de uma medição curta e precisa
ser acompanhado durante picos reais.

Após comprovar que o cluster consegue puxar o digest publicado, executar
`python3 scripts/patch_pool.py --kubeconfig <arquivo-local> --image <ci-browser por digest>`.
Acrescentar `--dry-run` para revisar o patch. Validar com
`python3 -m unittest discover -s scripts -p 'test_*.py'`.

O patch preserva autenticação, volumes e campos alheios, e usa resourceVersion
para recusar atualização concorrente. O kubeconfig nunca é copiado para o repo.
Mudanças no listener podem aguardar os jobs atuais terminarem; não apague runners
ocupados para acelerar a troca.

Rollback: reaplicar o digest anterior validado e o orçamento anterior através
da configuração, conservando os jobs em andamento. Acompanhar fila, duração,
CPU, memória, disco e falhas de startup. Caches dos projetos são separados por
repositório, plataforma, toolchain e entradas; estado do executor não é compartilhado.
