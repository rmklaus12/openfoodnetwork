class Enterprise < ActiveRecord::Base
  has_many :supplied_products, :class_name => 'Spree::Product', :foreign_key => 'supplier_id'
  has_many :distributed_orders, :class_name => 'Spree::Order', :foreign_key => 'distributor_id'
  belongs_to :address, :class_name => 'Spree::Address'
  has_many :product_distributions, :foreign_key => 'distributor_id', :dependent => :destroy
  has_many :distributed_products, :through => :product_distributions, :source => :product

  accepts_nested_attributes_for :address

  validates_presence_of :name
  validates_presence_of :address
  validates_associated :address

  after_initialize :initialize_country
  before_validation :set_unused_address_fields

  scope :by_name, order('name')
  scope :is_primary_producer, where(:is_primary_producer => true)
  scope :is_distributor, where(:is_distributor => true)
  scope :with_distributed_active_products_on_hand, lambda { joins(:distributed_products).where('spree_products.deleted_at IS NULL AND spree_products.available_on <= ? AND spree_products.count_on_hand > 0', Time.now).select('distinct(enterprises.*)') }

  scope :with_distributed_products_outer,
    joins('LEFT OUTER JOIN product_distributions ON product_distributions.distributor_id = enterprises.id').
    joins('LEFT OUTER JOIN spree_products ON spree_products.id = product_distributions.product_id')
  scope :with_order_cycles_outer,
    joins('LEFT OUTER JOIN exchanges ON (exchanges.receiver_id = enterprises.id)').
    joins('LEFT OUTER JOIN order_cycles ON (order_cycles.id = exchanges.order_cycle_id)')

  scope :active_distributors, lambda {
    with_distributed_products_outer.with_order_cycles_outer.
    where('(product_distributions.product_id IS NOT NULL AND spree_products.deleted_at IS NULL AND spree_products.available_on <= ? AND spree_products.count_on_hand > 0) OR (order_cycles.id IS NOT NULL AND order_cycles.orders_open_at <= ? AND order_cycles.orders_close_at >= ?)', Time.now, Time.now, Time.now).
    select('DISTINCT enterprises.*')
  }


  def has_supplied_products_on_hand?
    self.supplied_products.where('count_on_hand > 0').present?
  end

  def to_param
    "#{id}-#{name.parameterize}"
  end
  
  def distributed_variants
    Spree::Product.in_distributor(self).map { |product| product.variants + [product.master] }.flatten
  end


  private

  def initialize_country
    self.address ||= Spree::Address.new
    self.address.country = Spree::Country.find_by_id(Spree::Config[:default_country_id]) if self.address.new_record?
  end

  def set_unused_address_fields
    address.firstname = address.lastname = address.phone = 'unused' if address.present?
  end
end
