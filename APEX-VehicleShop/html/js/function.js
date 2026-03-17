// ============================================
// VAL VEHICLE SHOP - HELPER FUNCTIONS
// Legacy support and compatibility
// ============================================

var RESOURCE_NAME = window.RESOURCE_NAME || (typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'APEX-VehicleShop');
window.RESOURCE_NAME = RESOURCE_NAME;

// ============================================
// LEGACY SUPPORT FUNCTIONS
// ============================================

// Legacy Information function
function Information(carname, model, pricecar, kg, classcar) {
    if (typeof selectVehicle === 'function') {
        selectVehicle(carname, model, pricecar, kg, classcar);
    }
}

// Legacy buy popup function
function CLICKBUY(pricecar) {
    if (typeof openBuyModal === 'function') {
        openBuyModal();
    }
}

// Cancel buy
function Cancel_Buy_Vehicle() {
    if (typeof closeBuyModal === 'function') {
        closeBuyModal();
    }
}

// Payment selection
function Choose_Payment(payment) {
    if (typeof selectPayment === 'function') {
        selectPayment(payment);
    }
}

// ============================================
// LEGACY UPDATE FUNCTIONS
// ============================================

function UPDATE_BTN_PAYMENT(idclass) {
    // Now handled by selectPayment
}

function UPDATE_BTN_COLOR_1(idclass) {
    // Now handled by ChooseColorCar_1
}

function UPDATE_BTN_COLOR_2(idclass) {
    // Now handled by ChooseColorCar_2
}

function UPDATE_BTN_CATEGORY(idclass, idclass2, idclass3) {
    // Now handled by ChooseCategory
}

function UPDATE_BTN_CARNAME(idclass, idclass2, idclass3) {
    // Now handled by Choosecar
}
