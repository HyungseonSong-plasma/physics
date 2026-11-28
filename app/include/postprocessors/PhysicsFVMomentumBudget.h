#pragma once
#include "ElementPostprocessor.h"
#include "MooseVariableFV.h"
#include "MooseEnum.h"

// Reconstruct accepted-state steady RZ momentum terms without reading the RHS.
class PhysicsFVMomentumBudget : public ElementPostprocessor
{
public:
  static InputParameters validParams();
  PhysicsFVMomentumBudget(const InputParameters &);
  void initialize() override;
  void execute() override;
  void threadJoin(const UserObject &) override;
  void finalize() override;
  PostprocessorValue getValue() const override;

private:
  void add(Real);
  MooseVariableFVReal & _velocity;
  const Moose::Functor<ADReal> & _pressure;
  const Moose::Functor<ADReal> & _rho;
  const Moose::Functor<ADReal> & _mu;
  const PostprocessorValue & _mdot;
  const PostprocessorValue & _area;
  const unsigned int _component;
  const MooseEnum _term;
  const bool _absolute;
  Real _sum = 0;
};
