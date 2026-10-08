#!/usr/bin/env bash
set -e

# ---------- إعداد البيئة ----------
sudo apt update && sudo apt install -y \
    gcc-aarch64-linux-gnu \
    clang-14 \
    make \
    bc \
    bison \
    flex \
    libssl-dev \
    libelf-dev \
    libncurses5-dev \
    ccache \
    git

export CCACHE_DIR=$HOME/.ccache
export CROSS_COMPILE=aarch64-linux-gnu-
export CC=clang-14
export LLVM=1
export LLVM_IAS=1

# ---------- استنساخ المصدر ----------
WORKDIR=$HOME/kernel_build
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# المستودع الأصلي للجهاز
git clone https://github.com/SN-Abdullah-Al-Noman/SM-A315F.git a31_kernel
cd a31_kernel

# اختيار الفرع الذي يحتوي على النواة الحالية (مثلاً 5.4)
# إذا لم يكن هناك فرع، استخدم الـ tag المناسب أو master
git checkout origin/5.4 || git checkout master

# ---------- إضافة مصدر Linux 5.15 ----------
git remote add linux5.15 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
git fetch linux5.15

# إنشاء فرع للـ backport
git checkout -b bpf_backport_5.15

# ---------- دمج تغييرات BPF ----------
# هذا الجزء يختار الالتزامات (commits) التي تحتوي على كلمة "BPF"
# قد تحتاج لتعديل القائمة حسب ما يظهر لك تعارضات
COMMITS=$(git rev-list --reverse linux5.15/v5.15..linux5.15/v5.15 --grep='BPF' --invert-grep='test')
for C in $COMMITS; do
    git cherry-pick $C || {
        echo "فشل الالتزام $C - يرجى تصحيح التعارض يدويًا"
        exit 1
    }
done

# ---------- تكوين النواة ----------
make ARCH=arm64 menuconfig <<EOF
# تلقائيًا نختار الإعدادات المطلوبة
CONFIG_BPF=y
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_BPF_EVENTS=y
CONFIG_HAVE_EBPF_JIT=y
CONFIG_DEBUG_INFO_BTF=y
EOF

# حفظ التكوين للاحتمال المستقبلي
cp .config .config.backport

# ---------- بناء النواة ----------
make -j$(nproc) ARCH=arm64 O=out \
    CC=$CC \
    LLVM=$LLVM \
    LLVM_IAS=$LLVM_IAS \
    CROSS_COMPILE=$CROSS_COMPILE \
    Image.gz-dtb

# ---------- نتيجة البناء ----------
echo "✅ تم الانتهاء من بناء النواة"
ls -lh out/arch/arm64/boot/Image.gz-dtb

# إذا رغبت في إنشاء ملف zip للتحميل:
cd out/arch/arm64/boot
zip -9 lucreticus_a31_bpf5.15.zip Image.gz-dtb
echo "✅ الملف المضغوط جاهز: $(pwd)/lucreticus_a31_bpf5.15.zip"
