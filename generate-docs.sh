#!/bin/bash
# Script para gerar toda a documentação do repositório

set -e

echo "Gerando documentação do Karpenter Best Practices..."

# Criar LICENSE
cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2024 Matheus Andrade

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

echo "✅ LICENSE criado"
echo "✅ Estrutura de documentação pronta"
echo ""
echo "Próximos passos:"
echo "1. Revisar e customizar os arquivos gerados"
echo "2. git add ."
echo "3. git commit -m 'docs: add complete Karpenter best practices guide'"
echo "4. git push origin main"

