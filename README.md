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

`dockerNetworkMtu=1480` alinha a bridge padrão do Docker e as redes criadas por
Compose/actions à interface dos pods. As VPS usam MTU 1500 e o Calico IP-in-IP
reserva 20 bytes para o encapsulamento. Não altere o MTU global do Calico sem
medir o caminho físico. Os parâmetros Docker são `--mtu` e
`--default-network-opt=bridge=com.docker.network.driver.mtu=1480`:
o primeiro sozinho não cobre redes bridge criadas pelos jobs.
[Calico](https://docs.tigera.io/calico/latest/networking/configuring/mtu) e
[Docker](https://docs.docker.com/reference/cli/dockerd/#default-network-options).

Após comprovar que o cluster consegue puxar o digest publicado, executar
`python3 scripts/patch_pool.py --kubeconfig <arquivo-local> --image <ci-browser por digest>`.
Acrescentar `--dry-run` para revisar o patch. Validar com
`python3 -m unittest discover -s scripts -p 'test_*.py'`.

O comando persiste o template com `helm upgrade --reuse-values`, conservando
as referências de autenticação e os volumes. Customiza o modo DIND explicitamente
para aplicar recursos ao sidecar sem duplicar containers. O kubeconfig nunca é
copiado para o repo. O JSON patch com teste de resourceVersion fica disponível
para revisão (`--dry-run`) ou emergência (`--patch-only`).
Mudanças no listener podem aguardar os jobs atuais terminarem; não apague runners
ocupados para acelerar a troca.

No ARC 0.14.2 com estratégia `eventual`, uma mudança somente de capacidade pode
deixar o listener ausente e o conjunto antigo repondo ociosos. Ajustar o conjunto
antigo para `spec.replicas=0, spec.patchID=0` usa o mecanismo do ARC que conserva
jobs ocupados. A estratégia `immediate` também pode ser usada temporariamente
quando o template do runner não mudou, voltando a `eventual` após o listener
recriado. A estratégia do controlador não pertence a esta release do pool.

Rollback: reaplicar o digest anterior validado e o orçamento anterior através
da configuração, conservando os jobs em andamento. Acompanhar fila, duração,
CPU, memória, disco e falhas de startup. Caches dos projetos são separados por
repositório, plataforma, toolchain e entradas; estado do executor não é compartilhado.

## Piloto de provedor

O workflow manual `Runner pilot` executa o mesmo teste público em
`ubicloud-standard-2` ou `atplus-k8s`, com timeout de cinco minutos e permissão
somente de leitura do código. Mede PBKDF2 com Node 22, escrita com fsync de
128 MiB, download público, Docker/seccomp/AppArmor e restauração de cache.
As métricas ficam no resumo do job; fila e duração vêm do GitHub Actions.
Uma segunda execução no mesmo runner verifica o cache aquecido.

A integração da Ubicloud na org oferece Ubuntu x64/ARM64; o catálogo atual
não inclui Windows ou macOS. A conta está com Premium e cache transparente
habilitados. A tarifa observada para 2 vCPUs Premium é US$0,002/min, com teto
de US$0,01 por execução desse piloto. O teste não publica nem faz deploy de apps.
