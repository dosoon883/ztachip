#include <stdint.h>
#include <vector>
#include <stdarg.h>
#include "types.h"
#include "util.h"
#include "tensor.h"

// Default constructor.
// Tensor definition/allocation to be provided later

TENSOR::TENSOR() {
   m_shm=0;
   m_isAlias=false;
   m_dataType=TensorDataTypeUint8;
   m_dataElementLen=1;
   m_fmt=TensorFormatSplit;
   m_semantic=TensorSemanticUnknown;
   m_buf=0;
   m_size=0;
}

// Create a fully defined tensor.
// Also allocate memory for it

TENSOR::TENSOR(TensorDataType _dataType,TensorFormat _fmt,TensorSemantic _semantic,int numDim,...):TENSOR() {
   va_list args;
   int v;

   setDataType(_dataType);
   setFormat(_fmt);
   setSemantic(_semantic);
   va_start(args,numDim);
   for(int i=0;i < numDim;i++) {
      v=va_arg(args,int);
      m_dim.push_back(v);
   }
   m_size=Util::GetTensorSize(m_dim)*m_dataElementLen;
   allocate();
   va_end(args);
}

// Create tensor. Free previous allocation
// If _shm specified, tensor buffer has been created already so just reference it directly
// Otherwise allocate new buffer

ZtaStatus TENSOR::Create(TensorDataType _dataType,TensorFormat _fmt,TensorSemantic _semantic,std::vector<int> &dim,
                        ZTA_SHARED_MEM _shm) {
   if(m_shm && !m_isAlias) {
      ztahostFreeSharedMem(m_shm);
   }
   m_shm=0;
   m_isAlias=false;
   setDataType(_dataType);
   setFormat(_fmt);
   setSemantic(_semantic);
   setDimension(dim);
   if(_shm)
      allocate(_shm);
   else
      allocate();
   return ZtaStatusOk;
}

ZtaStatus TENSOR::Clone(TENSOR *other) {
   return Create(other->GetDataType(),other->GetFormat(),other->GetSemantic(),other->m_dim);
}

TENSOR::~TENSOR() {
   if(m_shm && !m_isAlias)
      ztahostFreeSharedMem(m_shm);
}

ZtaStatus TENSOR::setDataType(TensorDataType _dataType) {
   m_dataType=_dataType;
   switch(m_dataType) {
      case TensorDataTypeInt8:
      case TensorDataTypeUint8:
         m_dataElementLen=1;
         break;
      case TensorDataTypeInt16:
      case TensorDataTypeUint16:
         m_dataElementLen=2;
         break;
      case TensorDataTypeFloat32:
         m_dataElementLen=4;
         break;
      default:
         assert(0);
   }
   return ZtaStatusOk;
}

ZtaStatus TENSOR::setSemantic(TensorSemantic _semantic) {
   m_semantic=_semantic;
   return ZtaStatusOk;
}

ZtaStatus TENSOR::setFormat(TensorFormat fmt) {
   m_fmt=fmt;
   return ZtaStatusOk;
}

ZtaStatus TENSOR::setDimension(std::vector<int> &_dim) {
   m_dim.clear();
   m_dim=_dim;
   m_size = Util::GetTensorSize(m_dim)*m_dataElementLen;
   return ZtaStatusOk;
}

ZtaStatus TENSOR::allocate(ZTA_SHARED_MEM shm) {
   if(m_shm && !m_isAlias)
      ztahostFreeSharedMem(m_shm);
   m_isAlias=false;
   if(shm) {
      assert((int)ZTA_SHARED_MEM_LEN(shm)==m_size);
      m_shm=shm;
   } else {
      m_shm=ztahostAllocSharedMem(m_size);
   }
   m_buf=ZTA_SHARED_MEM_P(m_shm);
   return ZtaStatusOk;
}

// Set this tensor as an alias for another buffer

ZtaStatus TENSOR::Alias(TENSOR *other) {
   if(m_shm && !m_isAlias)
      ztahostFreeSharedMem(m_shm);
   m_shm=other->GetShm();
   m_isAlias=true;
   m_buf=ZTA_SHARED_MEM_P(m_shm);   
   assert(other->m_size==m_size);
   return ZtaStatusOk;
}


