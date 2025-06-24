# 基础镜像，使用NVIDIA CUDA 11.8开发环境（包含nvcc等编译工具）
FROM nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04

# 设置镜像维护者信息
LABEL maintainer="ChatTTS-Enhanced"
LABEL description="ChatTTS-Enhanced Docker Image with miniconda and dual service support"

# 设置时区和环境变量
ENV TZ=Asia/Shanghai
ENV PATH="/opt/miniconda3/bin:$PATH"
ENV CUDA_HOME=/usr/local/cuda
ENV PATH="/usr/local/cuda/bin:$PATH"

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 安装系统依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        vim \
        wget \
        curl \
        git \
        ca-certificates \
        htop \
        supervisor \
        build-essential \
        libsndfile1 \
        ffmpeg \
        bzip2 \
        && rm -rf /var/lib/apt/lists/*

# 下载并安装Miniconda3
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p /opt/miniconda3 && \
    rm /tmp/miniconda.sh && \
    /opt/miniconda3/bin/conda clean -afy

# 初始化conda
RUN /opt/miniconda3/bin/conda init bash

# 创建conda环境 Dlab python=3.10
RUN /opt/miniconda3/bin/conda create -n Dlab python=3.10 -y

# 在Dlab环境中安装PyTorch（使用pip安装最新稳定版本）
RUN /opt/miniconda3/bin/conda run -n Dlab pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# 设定工作目录
WORKDIR /workspace

# 复制ChatTTS-Enhanced项目代码（修改为当前目录）
COPY . /workspace/ChatTTS-Enhanced/

# 在Dlab环境中先固定NumPy版本，然后安装resemble-enhance
RUN /opt/miniconda3/bin/conda run -n Dlab pip install "numpy<2.0" && \
    /opt/miniconda3/bin/conda run -n Dlab pip install resemble-enhance

# 在Dlab环境中安装项目依赖（requirements.txt）
RUN if [ -f /workspace/ChatTTS-Enhanced/requirements.txt ]; then \
        /opt/miniconda3/bin/conda run -n Dlab pip install --no-cache-dir -r /workspace/ChatTTS-Enhanced/requirements.txt; \
    fi

# 在Dlab环境中安装WeTextProcessing
RUN /opt/miniconda3/bin/conda run -n Dlab pip install WeTextProcessing

# 创建启动脚本（激活conda环境）
RUN echo '#!/bin/bash\n\
# 激活conda环境\n\
source /opt/miniconda3/etc/profile.d/conda.sh\n\
conda activate Dlab\n\
\n\
cd /workspace/ChatTTS-Enhanced\n\
echo "Starting ChatTTS-Enhanced services..."\n\
echo "Using conda environment: Dlab"\n\
echo "Python version: $(python --version)"\n\
echo "PyTorch version: $(python -c \"import torch; print(torch.__version__)\")"\n\
\n\
echo "Starting API service..."\n\
python api.py &\n\
API_PID=$!\n\
echo "API service started with PID: $API_PID"\n\
\n\
echo "Starting WebUI service..."\n\
python webui/webui.py &\n\
WEBUI_PID=$!\n\
echo "WebUI service started with PID: $WEBUI_PID"\n\
\n\
echo "Both services are running."\n\
echo "API: http://0.0.0.0:5000"\n\
echo "WebUI: http://0.0.0.0:7860"\n\
\n\
wait $API_PID $WEBUI_PID\n\
' > /workspace/start_services.sh && \
    chmod +x /workspace/start_services.sh

# 暴露端口
EXPOSE 5000 7860

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:5000/health || curl -f http://localhost:7860 || exit 1

# 启动命令
CMD ["/workspace/start_services.sh"] 