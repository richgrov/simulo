#include "gpu.h"

#include <format>
#include <optional>
#include <set>
#include <stdexcept>
#include <vector>

#include <vulkan/vulkan_core.h>

#include "shader.h"

using namespace villa;

struct villa::QueueFamilies {
   uint32_t graphics;
   uint32_t presentation;
};

namespace {

#ifdef VILLA_DEBUG

const std::vector<const char *> validation_layers = {"VK_LAYER_KHRONOS_validation"};

void ensure_validation_layers_supported() {
   uint32_t total_layers;
   vkEnumerateInstanceLayerProperties(&total_layers, nullptr);

   std::vector<VkLayerProperties> all_layers(total_layers);
   vkEnumerateInstanceLayerProperties(&total_layers, all_layers.data());

   for (const char *const layer_name : validation_layers) {
      bool match = false;

      for (const auto &layer : all_layers) {
         if (strcmp(layer_name, layer.layerName) == 0) {
            match = true;
            break;
         }
      }

      if (!match) {
         throw std::runtime_error(std::format("validation layer {} not supported", layer_name));
      }
   }
}
#endif

std::optional<QueueFamilies> get_queue_families(VkPhysicalDevice device, VkSurfaceKHR surface) {
   uint32_t num_queue_families;
   vkGetPhysicalDeviceQueueFamilyProperties(device, &num_queue_families, nullptr);

   std::vector<VkQueueFamilyProperties> queue_families(num_queue_families);
   vkGetPhysicalDeviceQueueFamilyProperties(device, &num_queue_families, queue_families.data());

   QueueFamilies result;
   bool graphics_found = false;
   bool presentation_found = false;

   for (int i = 0; i < queue_families.size(); ++i) {
      if (!graphics_found && (queue_families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) == 1) {
         result.graphics = i;
         graphics_found = true;
      }

      if (!presentation_found) {
         VkBool32 supported = false;
         vkGetPhysicalDeviceSurfaceSupportKHR(device, i, surface, &supported);
         if (supported) {
            result.presentation = i;
            presentation_found = true;
         }
      }
   }

   if (!graphics_found || !presentation_found) {
      return std::nullopt;
   }

   return std::make_optional(result);
}

VkDevice create_logical_device(VkPhysicalDevice phys_device, const QueueFamilies &queue_families) {
   std::set<uint32_t> unique_queue_families = {
       queue_families.graphics, queue_families.presentation
   };

   std::vector<VkDeviceQueueCreateInfo> create_queues;
   create_queues.reserve(2);

   const float queue_priority = 1.0f;
   for (const uint32_t queue_family : unique_queue_families) {
      create_queues.push_back({
          .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
          .queueFamilyIndex = queue_family,
          .queueCount = 1,
          .pQueuePriorities = &queue_priority,
      });
   }

   VkPhysicalDeviceFeatures physical_device_features = {};

   static const char *swapchain_extension = VK_KHR_SWAPCHAIN_EXTENSION_NAME;
   VkDeviceCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
       .queueCreateInfoCount = static_cast<uint32_t>(create_queues.size()),
       .pQueueCreateInfos = create_queues.data(),
#ifdef VILLA_DEBUG
       .enabledLayerCount = static_cast<uint32_t>(validation_layers.size()),
       .ppEnabledLayerNames = validation_layers.data(),
#endif
       .enabledExtensionCount = 1,
       .ppEnabledExtensionNames = &swapchain_extension,
       .pEnabledFeatures = &physical_device_features,
   };

   VkDevice device;
   if (vkCreateDevice(phys_device, &create_info, nullptr, &device) != VK_SUCCESS) {
      throw std::runtime_error("failed to create logical device");
   }

   return device;
}

} // namespace

Gpu::Gpu()
    : vk_instance_(VK_NULL_HANDLE), physical_device_(VK_NULL_HANDLE), device_(VK_NULL_HANDLE),
      surface_(VK_NULL_HANDLE) {}

void Gpu::init(const std::vector<const char *> &extensions) {
   VkApplicationInfo app_info = {
       .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
       .applicationVersion = VK_MAKE_VERSION(1, 0, 0),
       .engineVersion = VK_MAKE_VERSION(1, 0, 0),
       .apiVersion = VK_API_VERSION_1_0,
   };

   VkInstanceCreateInfo create_info = {
       .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
       .pApplicationInfo = &app_info,
       .enabledExtensionCount = static_cast<uint32_t>(extensions.size()),
       .ppEnabledExtensionNames = extensions.data(),
   };

#ifdef VILLA_DEBUG
   ensure_validation_layers_supported();
   create_info.enabledLayerCount = static_cast<uint32_t>(validation_layers.size());
   create_info.ppEnabledLayerNames = validation_layers.data();
#endif

   if (vkCreateInstance(&create_info, nullptr, &vk_instance_) != VK_SUCCESS) {
      throw std::runtime_error("failed to create vulkan instance");
   }
}

Gpu::~Gpu() {
   vertex_shader_.deinit();
   fragment_shader_.deinit();

   swapchain_.deinit();

   if (device_ != VK_NULL_HANDLE) {
      vkDestroyDevice(device_, nullptr);
   }

   if (surface_ != VK_NULL_HANDLE) {
      vkDestroySurfaceKHR(vk_instance_, surface_, nullptr);
   }

   if (vk_instance_ != VK_NULL_HANDLE) {
      vkDestroyInstance(vk_instance_, nullptr);
   }
}

void Gpu::connect_to_surface(VkSurfaceKHR surface, uint32_t width, uint32_t height) {
   if (surface_ != VK_NULL_HANDLE) {
      throw std::runtime_error("surface already set");
   }

   surface_ = surface;

   QueueFamilies queue_familes;
   SwapchainCreationInfo swapchain_info;
   if (!init_physical_device(&queue_familes, &swapchain_info)) {
      throw std::runtime_error("no suitable physical device");
   }

   device_ = create_logical_device(physical_device_, queue_familes);

   VkQueue graphics_queue, presentation_queue;
   vkGetDeviceQueue(device_, queue_familes.graphics, 0, &graphics_queue);
   vkGetDeviceQueue(device_, queue_familes.presentation, 0, &presentation_queue);

   swapchain_.init(
       swapchain_info, {queue_familes.graphics, queue_familes.presentation}, physical_device_,
       device_, surface_, width, height
   );

   vertex_shader_.init(device_, "shader-vert.spv", ShaderType::kVertex);
   fragment_shader_.init(device_, "shader-frag.spv", ShaderType::kFragment);
}

bool Gpu::init_physical_device(
    QueueFamilies *out_families, SwapchainCreationInfo *out_swapchain_info
) {
   uint32_t num_devices;
   vkEnumeratePhysicalDevices(vk_instance_, &num_devices, nullptr);
   if (num_devices == 0) {
      throw std::runtime_error("no physical devices");
   }

   std::vector<VkPhysicalDevice> devices(num_devices);
   vkEnumeratePhysicalDevices(vk_instance_, &num_devices, devices.data());

   for (const auto &device : devices) {
      auto swapchain_info = Swapchain::get_creation_info(device, surface_);
      if (!swapchain_info.has_value()) {
         continue;
      }

      std::optional<QueueFamilies> queue_familes = get_queue_families(device, surface_);
      if (!queue_familes.has_value()) {
         continue;
      }

      physical_device_ = device;
      *out_families = queue_familes.value();
      *out_swapchain_info = swapchain_info.value();
      return true;
   }

   return false;
}
