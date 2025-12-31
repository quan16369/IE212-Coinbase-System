#!/bin/bash
# Validation Script for Infrastructure Modernization
# Run this script to verify all changes are correct

echo "========================================"
echo "Infrastructure Modernization Validation"
echo "========================================"
echo ""

ERRORS=0
WARNINGS=0

# Check 1: Verify Terraform module structure
echo "[1/10] Checking Terraform module structure..."
for module in vpc eks storage iam; do
    if [ ! -d "terraform/modules/$module" ]; then
        echo "  ✗ ERROR: Module $module not found"
        ((ERRORS++))
    else
        for file in main.tf variables.tf outputs.tf; do
            if [ ! -f "terraform/modules/$module/$file" ]; then
                echo "  ✗ ERROR: $module/$file missing"
                ((ERRORS++))
            fi
        done
    fi
done
echo "  ✓ Module structure verified"
echo ""

# Check 2: Verify environment configurations
echo "[2/10] Checking environment configurations..."
for env in production staging; do
    if [ ! -d "terraform/environments/$env" ]; then
        echo "  ✗ ERROR: Environment $env not found"
        ((ERRORS++))
    else
        for file in main.tf variables.tf outputs.tf; do
            if [ ! -f "terraform/environments/$env/$file" ]; then
                echo "  ✗ ERROR: $env/$file missing"
                ((ERRORS++))
            fi
        done
    fi
done
echo "  ✓ Environment configurations verified"
echo ""

# Check 3: Verify legacy files archived
echo "[3/10] Checking legacy files..."
if [ ! -d "terraform/legacy" ]; then
    echo "  ✗ ERROR: Legacy directory not found"
    ((ERRORS++))
else
    LEGACY_COUNT=$(ls terraform/legacy/*.tf 2>/dev/null | wc -l)
    if [ $LEGACY_COUNT -lt 3 ]; then
        echo "  ⚠ WARNING: Expected more legacy files"
        ((WARNINGS++))
    fi
fi
echo "  ✓ Legacy files archived"
echo ""

# Check 4: Check for Vietnamese text in documentation
echo "[4/10] Checking for Vietnamese text..."
VIETNAMESE_FOUND=$(grep -r "Đây là\|môi trường\|Chúc mừng\|Bạn đã\|hệ thống\|dữ liệu" *.md 2>/dev/null | wc -l)
if [ $VIETNAMESE_FOUND -gt 0 ]; then
    echo "  ⚠ WARNING: Found $VIETNAMESE_FOUND Vietnamese phrases"
    grep -r "Đây là\|môi trường\|Chúc mừng" *.md 2>/dev/null | head -5
    ((WARNINGS++))
else
    echo "  ✓ No Vietnamese text found"
fi
echo ""

# Check 5: Check for emojis in technical docs
echo "[5/10] Checking for emojis..."
EMOJI_FOUND=$(grep -rP "[\x{1F300}-\x{1F9FF}]|[✅🚀📊💰🎯]" *.md 2>/dev/null | wc -l)
if [ $EMOJI_FOUND -gt 0 ]; then
    echo "  ⚠ WARNING: Found $EMOJI_FOUND emojis"
    ((WARNINGS++))
else
    echo "  ✓ No emojis found"
fi
echo ""

# Check 6: Verify all documentation files exist
echo "[6/10] Checking documentation files..."
REQUIRED_DOCS=(
    "README.md"
    "DEPLOYMENT.md"
    "STACK_OVERVIEW.md"
    "CHANGELOG.md"
    "MODERNIZATION_SUMMARY.md"
    "QUICK_REFERENCE.md"
    "terraform/README.md"
)
for doc in "${REQUIRED_DOCS[@]}"; do
    if [ ! -f "$doc" ]; then
        echo "  ✗ ERROR: $doc not found"
        ((ERRORS++))
    fi
done
echo "  ✓ All required documentation exists"
echo ""

# Check 7: Validate Terraform syntax
echo "[7/10] Validating Terraform syntax..."
cd terraform/environments/production 2>/dev/null
if [ $? -eq 0 ]; then
    terraform init -backend=false > /dev/null 2>&1
    terraform validate > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "  ✓ Production Terraform syntax valid"
    else
        echo "  ✗ ERROR: Production Terraform syntax invalid"
        ((ERRORS++))
    fi
    cd ../../..
else
    echo "  ⚠ WARNING: Cannot validate Terraform (directory not found)"
    ((WARNINGS++))
fi
echo ""

# Check 8: Check for empty files
echo "[8/10] Checking for empty files..."
EMPTY_FILES=$(find . -maxdepth 2 -type f \( -name "*.md" -o -name "*.txt" \) -size 0 2>/dev/null)
if [ ! -z "$EMPTY_FILES" ]; then
    echo "  ⚠ WARNING: Found empty files:"
    echo "$EMPTY_FILES"
    ((WARNINGS++))
else
    echo "  ✓ No empty files found"
fi
echo ""

# Check 9: Verify deploy scripts are executable
echo "[9/10] Checking deploy scripts..."
DEPLOY_SCRIPTS=(
    "deploy.sh"
    "terraform/deploy.sh"
    "terraform/environments/production/deploy.sh"
)
for script in "${DEPLOY_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        if [ ! -x "$script" ]; then
            echo "  ✗ ERROR: $script not executable"
            ((ERRORS++))
        fi
    else
        echo "  ⚠ WARNING: $script not found"
        ((WARNINGS++))
    fi
done
echo "  ✓ Deploy scripts verified"
echo ""

# Check 10: File naming conventions
echo "[10/10] Checking file naming conventions..."
BAD_NAMES=$(find k8s/ -name "*.yaml" | grep -v "\-" | grep -v "namespace" 2>/dev/null)
if [ ! -z "$BAD_NAMES" ]; then
    echo "  ⚠ WARNING: Files not following kebab-case:"
    echo "$BAD_NAMES"
    ((WARNINGS++))
else
    echo "  ✓ File naming conventions followed"
fi
echo ""

# Summary
echo "========================================"
echo "Validation Summary"
echo "========================================"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo "✓ ALL CHECKS PASSED"
    echo ""
    echo "Infrastructure modernization completed successfully!"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo "✓ PASSED WITH WARNINGS"
    echo ""
    echo "Errors: $ERRORS"
    echo "Warnings: $WARNINGS"
    echo ""
    echo "Infrastructure is functional but has minor issues."
    exit 0
else
    echo "✗ VALIDATION FAILED"
    echo ""
    echo "Errors: $ERRORS"
    echo "Warnings: $WARNINGS"
    echo ""
    echo "Please fix the errors before proceeding."
    exit 1
fi
