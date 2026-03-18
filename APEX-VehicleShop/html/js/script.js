// ============================================
// VAL VEHICLE SHOP - MAIN SCRIPT
// Modern UI - Matching APEX-Garage theme
// ============================================

var RESOURCE_NAME = window.RESOURCE_NAME || (typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'APEX-VehicleShop');
window.RESOURCE_NAME = RESOURCE_NAME;

// ============================================
// CONFIG
// ============================================
const Config = {
    EnableTestDrive: true,
    EnableColorSelection: true,
    ShowVehicleImages: true,
    DefaultImageIcon: 'mingcute:car-3-fill',
    VATPercent: 6,
    Currency: '$',
    AnimationDelay: 40
};

// ============================================
// STATE VARIABLES
// ============================================
let choosemodelcar = null;
let choosepayment = null;
let currentPrice = 0;
let currentVehicleName = '';
let currentCanBuy = true;
let currentRequiredGrade = 0;
let money = 0;
let bank = 0;
let colorlist = {};
let color_1 = null;
let color_2 = null;
let timetestcarme = null;
let totalTestTime = 0;
let vehiclesData = {};
let currentShop = '';
let VehicleImages = {};

function normalizeVehicleImagePath(path) {
    if (!path || typeof path !== 'string') {
        return '';
    }

    // รองรับ config เดิมที่ใส่ html/images/... ให้ใช้งานกับ NUI ได้ทันที
    if (path.startsWith('html/')) {
        return path.replace(/^html\//, '');
    }

    return path;
}

// ============================================
// MESSAGE EVENT LISTENER
// ============================================
window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (data.openshop) {
        openShop(data);
    }
    
    if (data.closeui) {
        closeUI();
    }
    
    if (data.testcar) {
        startTestDrive(data);
    }
    
    if (data.closetime) {
        endTestDrive();
    }
});

// ============================================
// SHOP FUNCTIONS
// ============================================
function openShop(data) {
    const bottomPanel = document.getElementById('bottom-panel');
    const infoPanel = document.getElementById('vehicle-info-panel');
    
    // Use class-based animations for smooth entrance
    bottomPanel.classList.remove('hidden');
    bottomPanel.classList.add('visible');
    
    // Slight delay for right panel for staggered effect
    setTimeout(() => {
        infoPanel.classList.remove('hidden');
        infoPanel.classList.add('visible');
    }, 100);
    
    // Store data
    money = data.money || 0;
    bank = data.bank || 0;
    colorlist = data.colorlist || {};
    vehiclesData = data.vehiclesdata || {};
    currentShop = data.shop || '';
    VehicleImages = data.vehicleimages || {};
    
    // Update wallet display
    updateWalletDisplay();
    
    // Build categories
    buildCategories(data.vehicleCategorys);
    
    // Build vehicle list
    buildVehicleList(data.vehiclesdata, data.shop);
    
    // Build color palettes
    buildColorPalettes();
}

function closeUI() {
    // Reset state
    color_1 = null;
    color_2 = null;
    choosepayment = null;
    choosemodelcar = null;
    currentPrice = 0;
    currentVehicleName = '';
    currentCanBuy = true;
    currentRequiredGrade = 0;
    
    // Hide panels with class-based approach
    const bottomPanel = document.getElementById('bottom-panel');
    const infoPanel = document.getElementById('vehicle-info-panel');
    
    bottomPanel.classList.remove('visible');
    bottomPanel.classList.add('hidden');
    infoPanel.classList.remove('visible');
    infoPanel.classList.add('hidden');
    document.getElementById('buy-modal').style.display = 'none';
}

function updateWalletDisplay() {
    document.getElementById('money-display').textContent = Config.Currency + formatNumber(money);
    document.getElementById('bank-display').textContent = Config.Currency + formatNumber(bank);
}

function formatNumber(num) {
    return num.toLocaleString();
}

// ============================================
// BUILD CATEGORIES
// ============================================
function buildCategories(categories) {
    const categoryList = document.getElementById('category-list');
    categoryList.innerHTML = '';
    
    // Add "ALL" category
    categoryList.innerHTML += `
        <div class="category-item active" data-category="all" onclick="ChooseCategory('all')">
            ทั้งหมด
        </div>
    `;
    
    // Add other categories
    if (categories && categories.length > 0) {
        categories.forEach(item => {
            categoryList.innerHTML += `
                <div class="category-item" data-category="${item.index}" onclick="ChooseCategory('${item.index}')">
                    ${item.label}
                </div>
            `;
        });
    }
}

// ============================================
// BUILD VEHICLE LIST
// ============================================
function buildVehicleList(vehiclesdata, shop) {
    const vehicleList = document.getElementById('vehicle-list');
    vehicleList.innerHTML = '';
    
    let firstCar = null;
    let delay = 0;
    
    for (const key in vehiclesdata) {
        if (vehiclesdata[key] && Array.isArray(vehiclesdata[key])) {
            vehiclesdata[key].forEach(item => {
                if (item.typecar === shop) {
                    // Get vehicle image from VehicleImages config or item.image
                    let imageHtml = '';
                    const vehicleImage = (typeof VehicleImages !== 'undefined' && VehicleImages[item.model]) || item.image;
                    const vehicleImageSrc = normalizeVehicleImagePath(vehicleImage) || `images/vehicles/${item.model}.png`;
                    
                    if (Config.ShowVehicleImages) {
                        imageHtml = `<img src="${vehicleImageSrc}" alt="${item.name}" onerror="this.style.display='none'; this.parentElement.querySelector('iconify-icon').style.display='block';">
                                    <iconify-icon icon="${Config.DefaultImageIcon}" style="display:none;"></iconify-icon>`;
                    } else {
                        imageHtml = `<iconify-icon icon="${Config.DefaultImageIcon}"></iconify-icon>`;
                    }
                    
                    vehicleList.innerHTML += `
                        <div class="vehicle-card" 
                             data-categorycar="${item.category}" 
                             data-model="${item.model}"
                             data-name="${item.name}"
                             data-price="${item.price}"
                             data-class="${item.class || ''}"
                             data-kg="${item.kg || 0}"
                             data-can-buy="${item.canBuy === false ? 'false' : 'true'}"
                             data-required-grade="${item.requiredGrade || 0}"
                             style="animation-delay: ${delay}ms"
                             onclick="Choosecar(this)">
                            <div class="vehicle-card-image">
                                ${imageHtml}
                            </div>
                            <div class="vehicle-card-info">
                                <div class="vehicle-card-class">${item.class || 'ยานพาหนะ'}</div>
                                <div class="vehicle-card-name">${item.name}</div>
                                <div class="vehicle-card-price">${Config.Currency}${formatNumber(item.price)}</div>
                            </div>
                        </div>
                    `;
                    
                    // Save first car for auto-select
                    if (!firstCar) {
                        firstCar = {
                            name: item.name,
                            model: item.model,
                            price: item.price,
                            kg: item.kg || 0,
                            class: item.class || '',
                            canBuy: item.canBuy !== false,
                            requiredGrade: item.requiredGrade || 0
                        };
                    }
                    
                    delay += Config.AnimationDelay;
                }
            });
        }
    }
    
    // Auto-select first vehicle
    if (firstCar) {
        setTimeout(() => {
            const firstCard = document.querySelector(`[data-model="${firstCar.model}"]`);
            if (firstCard) {
                selectVehicle(firstCar.name, firstCar.model, firstCar.price, firstCar.kg, firstCar.class, firstCar.canBuy, firstCar.requiredGrade);
                firstCard.classList.add('active');
            }
        }, 100);
    }
}

// ============================================
// VEHICLE SELECTION
// ============================================
function Choosecar(element) {
    if (document.getElementById('buy-modal').style.display === 'block') {
        return;
    }
    
    const name = element.dataset.name;
    const model = element.dataset.model;
    const price = parseInt(element.dataset.price);
    const kg = parseInt(element.dataset.kg) || 0;
    const classcar = element.dataset.class || '';
    const canBuy = element.dataset.canBuy !== 'false';
    const requiredGrade = parseInt(element.dataset.requiredGrade || '0', 10) || 0;
    
    selectVehicle(name, model, price, kg, classcar, canBuy, requiredGrade);
    
    // Update active state
    document.querySelectorAll('.vehicle-card').forEach(card => {
        card.classList.remove('active');
    });
    element.classList.add('active');
}

function updateBuyButtonState() {
    const buyBtn = document.getElementById('buy-btn');
    const buyBtnLabel = document.getElementById('buy-btn-label');
    const statusMessage = document.getElementById('buy-status-message');

    if (!buyBtn || !buyBtnLabel || !statusMessage) {
        return;
    }

    if (currentCanBuy) {
        buyBtn.classList.remove('locked');
        buyBtnLabel.textContent = 'ซื้อยานพาหนะ';
        statusMessage.textContent = '';
        return;
    }

    buyBtn.classList.add('locked');
    buyBtnLabel.textContent = 'ยศคุณไม่ถึง';
    statusMessage.textContent = currentRequiredGrade > 0 ? `ยศขั้นต่ำที่ต้องการ: ${currentRequiredGrade}` : 'ยศคุณไม่ถึง';
}

function selectVehicle(carname, model, pricecar, kg, classcar, canBuy = true, requiredGrade = 0) {
    choosemodelcar = model;
    currentPrice = pricecar;
    currentVehicleName = carname;
    currentCanBuy = canBuy;
    currentRequiredGrade = requiredGrade;
    
    // Update info panel
    document.getElementById('vehicle-class').textContent = classcar || 'ยานพาหนะ';
    document.getElementById('vehicle-name').textContent = carname;
    document.getElementById('vehicle-price').textContent = Config.Currency + formatNumber(pricecar);
    updateBuyButtonState();
    
    // Notify game to show vehicle
    $.post('https://' + RESOURCE_NAME + '/choosecar', JSON.stringify({
        model: model,
    }));
}

// Legacy function for compatibility
function Information(carname, model, pricecar, kg, classcar) {
    selectVehicle(carname, model, pricecar, kg, classcar, true, 0);
}

// ============================================
// CATEGORY SELECTION
// ============================================
function ChooseCategory(category) {
    if (document.getElementById('buy-modal').style.display === 'block') {
        return;
    }
    
    // Update active state
    document.querySelectorAll('.category-item').forEach(item => {
        item.classList.remove('active');
    });
    document.querySelector(`[data-category="${category}"]`)?.classList.add('active');
    
    // Filter vehicles
    document.querySelectorAll('.vehicle-card').forEach(card => {
        if (category === 'all') {
            card.style.display = 'flex';
        } else {
            if (card.dataset.categorycar === category) {
                card.style.display = 'flex';
            } else {
                card.style.display = 'none';
            }
        }
    });
}

// ============================================
// COLOR SELECTION - Based on Config ColorList
// ColorList structure: { [1]: { colorName: { background, r, g, b } }, [2]: {...} }
// ============================================
function buildColorPalettes() {
    const palette1 = document.getElementById('color-palette-1');
    const palette2 = document.getElementById('color-palette-2');
    const colorSection = document.getElementById('color-section');
    const colorGroup1 = palette1.parentElement;
    const colorGroup2 = palette2.parentElement;
    
    palette1.innerHTML = '';
    palette2.innerHTML = '';
    
    if (!Config.EnableColorSelection) {
        colorSection.style.display = 'none';
        return;
    }
    
    let hasPrimaryColors = false;
    let hasSecondaryColors = false;
    
    // Handle Config ColorList structure: { 1: { colorName: {...} }, 2: { colorName: {...} } }
    // Primary colors from colorlist[1] or colorlist['1']
    let primaryColorsObj = colorlist[1] || colorlist['1'] || colorlist || {};
    let secondaryColorsObj = colorlist[2] || colorlist['2'] || {};
    
    // If colorlist is flat (no [1]/[2]), try to use it as primary
    if (Object.keys(primaryColorsObj).length === 0 && typeof colorlist === 'object') {
        // Check if first key has background property (it's a color object)
        const firstKey = Object.keys(colorlist)[0];
        if (firstKey && colorlist[firstKey] && colorlist[firstKey].background) {
            primaryColorsObj = colorlist;
        }
    }
    
    // If secondary colors are not provided, mirror primary colors so both palettes are available
    if (Object.keys(secondaryColorsObj).length === 0 && Object.keys(primaryColorsObj).length > 0) {
        secondaryColorsObj = primaryColorsObj;
    }

    // Build primary color palette from object
    const primaryKeys = Object.keys(primaryColorsObj);
    if (primaryKeys.length > 0) {
        hasPrimaryColors = true;
        primaryKeys.forEach((colorName) => {
            const item = primaryColorsObj[colorName];
            const bgColor = item.background || '#666';
            
            palette1.innerHTML += `
                <div class="color-swatch" 
                     id="color1-${colorName}"
                     data-color="${colorName}"
                     style="background: ${bgColor}"
                     title="${colorName}"
                     onclick="ChooseColorCar_1('${colorName}')">
                </div>
            `;
        });
    }
    
    // Build secondary color palette from object
    const secondaryKeys = Object.keys(secondaryColorsObj);
    if (secondaryKeys.length > 0) {
        hasSecondaryColors = true;
        secondaryKeys.forEach((colorName) => {
            const item = secondaryColorsObj[colorName];
            const bgColor = item.background || '#666';
            
            palette2.innerHTML += `
                <div class="color-swatch" 
                     id="color2-${colorName}"
                     data-color="${colorName}"
                     style="background: ${bgColor}"
                     title="${colorName}"
                     onclick="ChooseColorCar_2('${colorName}')">
                </div>
            `;
        });
    }
    
    // Show/hide color groups and section
    const hasAnyColors = hasPrimaryColors || hasSecondaryColors;
    
    if (hasAnyColors) {
        colorSection.style.display = 'block';
        // Show/hide individual color groups
        colorGroup1.style.display = hasPrimaryColors ? 'block' : 'none';
        colorGroup2.style.display = hasSecondaryColors ? 'block' : 'none';
    } else {
        colorSection.style.display = 'none';
    }
}

function ChooseColorCar_1(colorName) {
    color_1 = colorName;
    
    // Update active state
    document.querySelectorAll('#color-palette-1 .color-swatch').forEach(swatch => {
        swatch.classList.remove('active');
    });
    document.getElementById(`color1-${colorName}`)?.classList.add('active');
    
    // Notify game with color name (matches Config ColorList key)
    $.post('https://' + RESOURCE_NAME + '/choosecolor1', JSON.stringify({
        color: colorName,
    }));
}

function ChooseColorCar_2(colorName) {
    color_2 = colorName;
    
    // Update active state
    document.querySelectorAll('#color-palette-2 .color-swatch').forEach(swatch => {
        swatch.classList.remove('active');
    });
    document.getElementById(`color2-${colorName}`)?.classList.add('active');
    
    // Notify game with color name (matches Config ColorList key)
    $.post('https://' + RESOURCE_NAME + '/choosecolor2', JSON.stringify({
        color: colorName,
    }));
}

// ============================================
// 360 DEGREE VIEW - LEFT CLICK DRAG ROTATION
// ============================================
let isDragging = false;
let lastMouseX = 0;

function init360DragView() {
    document.addEventListener('mousedown', function(e) {
        // Only left click (button 0)
        if (e.button === 0 && choosemodelcar) {
            // Don't start drag if clicking on UI elements
            const target = e.target;
            const isOnUI = target.closest('.bottom-panel') || 
                          target.closest('.right-panel') || 
                          target.closest('.buy-modal-container') ||
                          target.closest('.testdrive-overlay') ||
                          target.closest('button') ||
                          target.closest('.vehicle-card') ||
                          target.closest('.category-item') ||
                          target.closest('.color-swatch') ||
                          target.closest('.payment-btn');
            
            if (!isOnUI) {
                isDragging = true;
                lastMouseX = e.clientX;
                document.body.style.cursor = 'grabbing';
            }
        }
    });
    
    document.addEventListener('mousemove', function(e) {
        if (isDragging) {
            const deltaX = e.clientX - lastMouseX;
            
            // Send rotation delta to game (positive = rotate right, negative = rotate left)
            if (Math.abs(deltaX) > 2) {
                $.post('https://' + RESOURCE_NAME + '/rotate360', JSON.stringify({
                    deltaX: deltaX,
                }));
                lastMouseX = e.clientX;
            }
        }
    });
    
    document.addEventListener('mouseup', function(e) {
        if (e.button === 0) {
            isDragging = false;
            document.body.style.cursor = 'default';
        }
    });
    
    // Cancel drag if mouse leaves window
    document.addEventListener('mouseleave', function() {
        isDragging = false;
        document.body.style.cursor = 'default';
    });
}

// ============================================
// TEST DRIVE
// ============================================
function TestDrive() {
    if (!Config.EnableTestDrive || !choosemodelcar) return;
    
    $.post('https://' + RESOURCE_NAME + '/testcar', JSON.stringify({
        carname: choosemodelcar,
    }));
}

function startTestDrive(data) {
    const overlay = document.getElementById('testdrive-overlay');
    overlay.classList.add('visible');
    
    totalTestTime = +data.time;
    let timeleft = totalTestTime;
    
    document.getElementById('testdrive-carname').textContent = data.carname || currentVehicleName;
    
    timetestcarme = setInterval(function() {
        const minutes = Math.floor(timeleft / 60);
        const seconds = timeleft % 60;
        
        document.getElementById('testdrive-timer').textContent = 
            minutes.toString().padStart(2, '0') + ':' + 
            seconds.toString().padStart(2, '0');
        
        const progressPercent = ((totalTestTime - timeleft) / totalTestTime) * 100;
        document.getElementById('timer-fill').style.width = (100 - progressPercent) + '%';
        
        if (timeleft === 0) {
            endTestDrive();
            $.post('https://' + RESOURCE_NAME + '/timeouttest');
        }
        
        timeleft--;
    }, 1000);
}

function endTestDrive() {
    if (timetestcarme !== null) {
        document.getElementById('testdrive-overlay').classList.remove('visible');
        clearInterval(timetestcarme);
        timetestcarme = null;
    }
}

// ============================================
// BUY MODAL
// ============================================
function openBuyModal() {
    if (!choosemodelcar || !currentCanBuy) return;
    
    const modal = document.getElementById('buy-modal');
    modal.style.display = 'block';
    
    // Reset payment selection
    choosepayment = null;
    document.querySelectorAll('.payment-btn').forEach(btn => {
        btn.classList.remove('active');
    });
    
    // Update modal info
    document.getElementById('modal-vehicle-name').textContent = currentVehicleName;
    document.getElementById('cash-amount').textContent = Config.Currency + formatNumber(currentPrice);
    
    const priceWithVat = Math.floor(currentPrice * (1 + Config.VATPercent / 100));
    document.getElementById('bank-amount').textContent = Config.Currency + formatNumber(priceWithVat) + ` (+${Config.VATPercent}% ภาษีมูลค่าเพิ่ม)`;
}

function closeBuyModal() {
    document.getElementById('buy-modal').style.display = 'none';
    choosepayment = null;
}

function selectPayment(method) {
    choosepayment = method;
    
    // Update active state
    document.querySelectorAll('.payment-btn').forEach(btn => {
        btn.classList.remove('active');
    });
    
    if (method === 'money') {
        document.getElementById('payment-cash').classList.add('active');
    } else {
        document.getElementById('payment-bank').classList.add('active');
    }
}

function confirmPurchase() {
    if (!choosepayment || !choosemodelcar || !currentCanBuy) {
        return;
    }
    
    $.post('https://' + RESOURCE_NAME + '/buycar', JSON.stringify({
        color1: color_1,
        color2: color_2,
        carname: choosemodelcar,
        payment: choosepayment
    }));
    
    closeUI();
}

// Alias for compatibility
function BUYCAR() {
    confirmPurchase();
}

// ============================================
// SCROLL FUNCTIONS
// ============================================
function scrollVehicles(direction) {
    const list = document.getElementById('vehicle-list');
    const scrollAmount = 250;
    
    if (direction === 'left') {
        list.scrollBy({ left: -scrollAmount, behavior: 'smooth' });
    } else {
        list.scrollBy({ left: scrollAmount, behavior: 'smooth' });
    }
}

// ============================================
// KEYBOARD EVENTS
// ============================================
document.addEventListener('keyup', function(e) {
    if (e.key === 'Escape') {
        if (document.getElementById('buy-modal').style.display === 'block') {
            closeBuyModal();
        } else {
            closeUI();
            $.post('https://' + RESOURCE_NAME + '/quit');
        }
    }
});

// ============================================
// INITIALIZATION
// ============================================
document.addEventListener('DOMContentLoaded', function() {
    // Use class-based hiding for smooth animations
    document.getElementById('bottom-panel').classList.add('hidden');
    document.getElementById('vehicle-info-panel').classList.add('hidden');
    document.getElementById('testdrive-overlay').classList.remove('visible');
    document.getElementById('buy-modal').style.display = 'none';
    
    // Initialize 360 drag rotation
    init360DragView();
});
