module Spree
  # Handles checkout logic.  This is somewhat contrary to standard REST convention since there is not actually a
  # Checkout object.  There's enough distinct logic specific to checkout which has nothing to do with updating an
  # order that this approach is waranted.
  class CheckoutController < BaseController
    ssl_required

    before_filter :load_order, :except => :complete

    rescue_from Spree::Core::GatewayError, :with => :rescue_from_spree_gateway_error

    respond_to :html

    def address
      render :edit
    end

    def update_address
      update_order!
    end

    def delivery
      render :edit
    end

    def update_delivery
      update_order!
    end

    def payment
      render :edit
    end

    def update_payment
      update_order!
    end

    def complete
      order = Order.find(session[:order_id])
      flash.notice = t(:order_processed_successfully)
      flash[:commerce_tracking] = "nothing special"
      redirect_to(order_path(order.to_param))
      state_callback(:after)
    end

    def confirm
      render :edit
    end

    def update_confirm
      update_order!
    end

    # Updates the order and advances to the next state (when possible.)
    def update
      if @order.update_attributes(object_params)
        fire_event('spree.checkout.update')

        if @order.next
          state_callback(:after)
        else
          flash[:error] = t(:payment_processing_failed)
          respond_with(@order, :location => checkout_state_path(@order.state))
          return
        end

        if @order.state == "complete" || @order.completed?
          flash.notice = t(:order_processed_successfully)
          flash[:commerce_tracking] = "nothing special"
          respond_with(@order, :location => completion_route)
        else
          respond_with(@order, :location => checkout_state_path(@order.state))
        end
      else
        respond_with(@order) { |format| format.html { render :edit } }
      end
    end

    private
      def update_order!
        if @order.update_attributes(object_params)
          fire_event('spree.checkout.update')
          @order.next
          state_callback(:after)
          redirect_to [@order.state, :checkout]
        else
          render :edit
        end
      end

      # Provides a route to redirect after order completion
      def completion_route
        order_path(@order)
      end

      def object_params
        # For payment step, filter order parameters to produce the expected nested attributes for a single payment and its source, discarding attributes for payment methods other than the one selected
        if @order.payment?
          if params[:payment_source].present? && source_params = params.delete(:payment_source)[params[:order][:payments_attributes].first[:payment_method_id].underscore]
            params[:order][:payments_attributes].first[:source_attributes] = source_params
          end
          if (params[:order][:payments_attributes])
            params[:order][:payments_attributes].first[:amount] = @order.total
          end
        end
        params[:order]
      end

      def load_order
        @order = current_order
        redirect_to cart_path and return unless @order and @order.checkout_allowed?
        raise_insufficient_quantity and return if @order.insufficient_stock_lines.present?
        @order.state = params[:action] unless params[:action].include?("update")
        state_callback(:before)
      end

      def raise_insufficient_quantity
        flash[:error] = t(:spree_inventory_error_flash_for_insufficient_quantity)
        redirect_to cart_path
      end

      def state_callback(before_or_after = :before)
        method_name = :"#{before_or_after}_#{@order.state}"
        send(method_name) if respond_to?(method_name, true)
      end

      def before_address
        past_order = @order.user.orders.complete.order("id desc").first
        if past_order
          @order.bill_address = past_order.bill_address.clone if past_order.bill_address
        end
        @order.bill_address ||= current_user.bill_address if respond_to?(:current_user) && current_user
        @order.bill_address ||= Address.default
        @order.ship_address ||= Address.default
      end

      def before_delivery
        return if params[:order].present?
        @order.shipping_method ||= (@order.rate_hash.first && @order.rate_hash.first[:shipping_method])
      end

      def before_payment
        current_order.payments.destroy_all if request.put?
      end

      def rescue_from_spree_gateway_error
        flash[:error] = t(:spree_gateway_error_flash_for_checkout)
        render :edit
      end
  end
end
